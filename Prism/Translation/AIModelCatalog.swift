import Foundation

/// Consulta a API do provedor, escolhe o melhor modelo ativo para tradução e evita ids descontinuados.
enum AIModelCatalog {
    struct RefreshResult: Equatable {
        var updatedProviders: [ProviderKind] = []
        var notes: [String] = []

        var didChange: Bool { !updatedProviders.isEmpty }
    }

    private static let cacheKey = "AIModelCatalog.cache.v1"
    private static let lastRefreshKey = "AIModelCatalog.lastRefresh"
    private static let minimumRefreshInterval: TimeInterval = 12 * 60 * 60

    /// Modelos já conhecidos como retirados / problemáticos — migrar mesmo sem lista ao vivo.
    static let knownDeprecatedModels: [ProviderKind: Set<String>] = [
        .gemini: [
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
            "gemini-2.0-flash",
            "gemini-2.0-flash-lite",
            "gemini-1.5-flash",
            "gemini-1.5-pro",
            "gemini-pro",
            "gemini-pro-vision"
        ],
        .groq: [
            "llama3-8b-8192",
            "llama3-70b-8192",
            "mixtral-8x7b-32768",
            "gemma-7b-it",
            "gemma2-9b-it"
        ],
        .deepSeek: [
            "deepseek-coder",
            "deepseek-v3"
        ],
        .mistral: [
            "mistral-tiny",
            "mistral-small-2402",
            "open-mistral-7b"
        ]
    ]

    /// Atualiza modelos configurados quando estão descontinuados ou ausentes na API.
    @MainActor
    static func refreshModels(
        settings: inout AppSettings,
        force: Bool = false,
        kinds: [ProviderKind]? = nil
    ) async -> RefreshResult {
        let targets = (kinds ?? ProviderKind.allCases.filter(\.supportsLiveModelCatalog))
            .filter(\.supportsLiveModelCatalog)
        guard !targets.isEmpty else { return RefreshResult() }

        if !force, !shouldRefresh() {
            // Ainda assim migra ids hardcoded como descontinuados (sem rede).
            return migrateKnownDeprecated(settings: &settings, kinds: targets)
        }

        var result = RefreshResult()
        var cache = loadCache()

        for kind in targets {
            do {
                let live = try await fetchLiveModelIDs(for: kind)
                guard !live.isEmpty else {
                    result.notes.append("\(kind.displayName): lista vazia — mantendo modelo atual.")
                    continue
                }
                cache.modelsByProvider[kind.rawValue] = Array(live).sorted()
                cache.fetchedAtByProvider[kind.rawValue] = Date()

                let current = settings.model(for: kind)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let recommended = pickBestModel(for: kind, available: live)
                    ?? kind.defaultModel
                    ?? current

                let currentMissing = !current.isEmpty && !live.contains(current)
                let currentDeprecated = isKnownDeprecated(kind, model: current)
                let shouldUpgradeDefault =
                    current.isEmpty
                    || current == kind.defaultModel
                    || knownFormerDefaults(for: kind).contains(current)

                if currentMissing || currentDeprecated
                    || (shouldUpgradeDefault && recommended != current && live.contains(recommended))
                {
                    if recommended != current, !recommended.isEmpty {
                        settings.setModel(recommended, for: kind)
                        result.updatedProviders.append(kind)
                        let reason =
                            currentMissing
                            ? "indisponível na API"
                            : (currentDeprecated ? "descontinuado" : "melhor opção ativa para tradução")
                        result.notes.append(
                            "\(kind.displayName): \(current.isEmpty ? "—" : current) → \(recommended) (\(reason))."
                        )
                        AppLog.info(
                            .engine,
                            "Catálogo \(kind.displayName): modelo \(current.isEmpty ? "—" : current) → \(recommended) (\(reason))"
                        )
                    }
                }
            } catch {
                result.notes.append("\(kind.displayName): \(error.localizedDescription)")
                AppLog.warning(
                    .engine,
                    "Catálogo \(kind.displayName) falhou: \(error.localizedDescription)"
                )
                // Offline / sem chave: ainda migra lista local de deprecated.
                let local = migrateKnownDeprecated(settings: &settings, kinds: [kind])
                result.updatedProviders.append(contentsOf: local.updatedProviders)
                result.notes.append(contentsOf: local.notes)
            }
        }

        saveCache(cache)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRefreshKey)
        return result
    }

    /// Escolhe o primeiro modelo da lista de preferência que exista em `available`.
    static func pickBestModel(for kind: ProviderKind, available: Set<String>) -> String? {
        for candidate in kind.preferredModelsForTranslation where available.contains(candidate) {
            return candidate
        }
        // Fallback: preferir ids com flash/lite/small/instant/free no nome.
        let scored = available.sorted { a, b in
            score(a, for: kind) > score(b, for: kind)
        }
        return scored.first
    }

    static func isKnownDeprecated(_ kind: ProviderKind, model: String) -> Bool {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return knownDeprecatedModels[kind]?.contains(trimmed) == true
    }

    // MARK: - Fetch

    private static func fetchLiveModelIDs(for kind: ProviderKind) async throws -> Set<String> {
        switch kind {
        case .gemini:
            return try await fetchGeminiModels(apiKey: key(for: kind))
        case .groq, .mistral, .deepSeek, .openRouter:
            guard let base = kind.openAICompatibleBaseURL else { return [] }
            var headers: [String: String] = [:]
            if kind == .openRouter {
                headers["HTTP-Referer"] = "https://prism.translate"
                headers["X-Title"] = "Prism"
            }
            return try await fetchOpenAICompatibleModels(
                baseURL: base,
                apiKey: key(for: kind),
                extraHeaders: headers
            )
        default:
            return []
        }
    }

    private static func key(for kind: ProviderKind) throws -> String {
        guard let keychain = kind.apiKeychainKey,
            let value = KeychainStore.string(for: keychain)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            throw TranslationError.invalidConfiguration(
                "Configure a API key de \(kind.displayName) para atualizar modelos."
            )
        }
        return value
    }

    private static func fetchOpenAICompatibleModels(
        baseURL: String,
        apiKey: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> Set<String> {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/models") else {
            throw TranslationError.invalidConfiguration("URL de modelos inválida")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.httpStatus(http.statusCode, body)
        }

        struct ModelsResponse: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]?
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return Set((decoded.data ?? []).map(\.id))
    }

    private static func fetchGeminiModels(apiKey: String) async throws -> Set<String> {
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models"
        )
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        guard let url = components?.url else {
            throw TranslationError.invalidConfiguration("URL Gemini inválida")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.httpStatus(http.statusCode, body)
        }

        struct ListResponse: Decodable {
            struct Model: Decodable {
                let name: String?
                let supportedGenerationMethods: [String]?
            }
            let models: [Model]?
        }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        var ids = Set<String>()
        for model in decoded.models ?? [] {
            let methods = model.supportedGenerationMethods ?? []
            guard methods.contains("generateContent") else { continue }
            guard var name = model.name, !name.isEmpty else { continue }
            if name.hasPrefix("models/") {
                name = String(name.dropFirst("models/".count))
            }
            ids.insert(name)
        }
        // Aliases estáveis que a API pode não listar explicitamente.
        ids.insert("gemini-flash-lite-latest")
        ids.insert("gemini-flash-latest")
        return ids
    }

    // MARK: - Local migration / cache

    private static func migrateKnownDeprecated(
        settings: inout AppSettings,
        kinds: [ProviderKind]
    ) -> RefreshResult {
        var result = RefreshResult()
        for kind in kinds {
            let current = settings.model(for: kind)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard isKnownDeprecated(kind, model: current) else { continue }
            let fallback = kind.defaultModel ?? kind.preferredModelsForTranslation.first
            guard let fallback, fallback != current else { continue }
            settings.setModel(fallback, for: kind)
            result.updatedProviders.append(kind)
            result.notes.append(
                "\(kind.displayName): \(current) → \(fallback) (descontinuado)."
            )
        }
        return result
    }

    private static func knownFormerDefaults(for kind: ProviderKind) -> Set<String> {
        // Defaults antigos que ainda possam estar gravados — candidatos a upgrade silencioso
        // quando a API confirma um modelo preferido mais novo.
        switch kind {
        case .gemini:
            return [
                "gemini-3.1-flash-lite",
                "gemini-3.5-flash-lite",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.0-flash",
                "gemini-2.0-flash-lite",
                "gemini-1.5-flash"
            ]
        case .deepSeek:
            return ["deepseek-v4-flash"]
        case .groq:
            return ["llama3-8b-8192", "llama-3.1-70b-versatile"]
        case .mistral:
            return ["mistral-tiny", "mistral-small-2402"]
        case .openRouter:
            return ["meta-llama/llama-3.1-8b-instruct:free"]
        default:
            return []
        }
    }

    private static func score(_ model: String, for kind: ProviderKind) -> Int {
        let lower = model.lowercased()
        var value = 0
        if lower.contains("flash-lite") || lower.contains("flash_lite") { value += 50 }
        if lower.contains("instant") { value += 45 }
        if lower.contains("small") { value += 40 }
        if lower.contains("flash") { value += 35 }
        if lower.contains(":free") || lower.hasSuffix("/free") { value += 40 }
        if lower.contains("lite") { value += 25 }
        if lower.contains("chat") { value += 20 }
        if lower.contains("latest") { value += 15 }
        if lower.contains("instruct") { value += 10 }
        if lower.contains("embed") || lower.contains("tts") || lower.contains("image")
            || lower.contains("whisper") || lower.contains("audio")
        {
            value -= 100
        }
        if kind == .openRouter, !lower.contains("free") { value -= 30 }
        return value
    }

    private static func shouldRefresh() -> Bool {
        let last = UserDefaults.standard.double(forKey: lastRefreshKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= minimumRefreshInterval
    }

    private struct Cache: Codable {
        var modelsByProvider: [String: [String]] = [:]
        var fetchedAtByProvider: [String: Date] = [:]
    }

    private static func loadCache() -> Cache {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
            let decoded = try? JSONDecoder().decode(Cache.self, from: data)
        else {
            return Cache()
        }
        return decoded
    }

    private static func saveCache(_ cache: Cache) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
