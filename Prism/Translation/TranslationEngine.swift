import Foundation

@MainActor
final class TranslationEngine {
    private var settings: AppSettings
    private let appleBridge: AppleTranslationBridge

    private struct CacheKey: Hashable {
        let text: String
        let from: String?
        let to: String
        let provider: String
    }

    /// Small LRU of recent translations (same phrase re-translated instantly).
    private var cacheOrder: [CacheKey] = []
    private var cacheValues: [CacheKey: TranslationOutcome] = [:]
    private static let maxCacheEntries = 64

    init(settings: AppSettings, appleBridge: AppleTranslationBridge) {
        self.settings = settings
        self.appleBridge = appleBridge
    }

    func updateSettings(_ settings: AppSettings) {
        let providerChanged = settings.providerKind != self.settings.providerKind
        let languagesChanged =
            settings.incomingSourceLanguage != self.settings.incomingSourceLanguage
            || settings.incomingTargetLanguage != self.settings.incomingTargetLanguage
            || settings.outgoingSourceLanguage != self.settings.outgoingSourceLanguage
            || settings.outgoingTargetLanguage != self.settings.outgoingTargetLanguage
        self.settings = settings
        if providerChanged || languagesChanged {
            AppLog.info(
                .engine,
                "settings mudaram — limpando cache (providerChanged=\(providerChanged), languagesChanged=\(languagesChanged), provider=\(settings.providerKind.rawValue))"
            )
            clearCache()
        }
    }

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        let key = CacheKey(
            text: text,
            from: from,
            to: to,
            provider: settings.providerKind.rawValue
        )
        AppLog.debug(
            .engine,
            "translate pedido — provider=\(settings.providerKind.rawValue), from=\(from ?? "auto"), to=\(to), chars=\(text.count), cacheSize=\(cacheValues.count)"
        )
        if let cached = cacheValues[key] {
            touchCache(key)
            AppLog.info(.engine, "cache HIT — retornando sem chamar provider (\(cached.text.count) chars)")
            if from == nil, cached.detectedSourceLanguage == nil,
               let detected = LanguageDetector.detect(in: text)
            {
                let enriched = TranslationOutcome(
                    text: cached.text,
                    detectedSourceLanguage: detected
                )
                storeCache(key, value: enriched)
                AppLog.info(.engine, "cache enriquecido com detecção local: \(detected)")
                return enriched
            }
            return cached
        }

        let provider = makeProvider()
        AppLog.info(
            .engine,
            "cache MISS — chamando provider '\(provider.displayName)' (id=\(provider.id))"
        )
        let started = Date()
        do {
            var outcome = try await provider.translate(text, from: from, to: to)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if from == nil, outcome.detectedSourceLanguage == nil,
               let detected = LanguageDetector.detect(in: text)
            {
                outcome = TranslationOutcome(
                    text: outcome.text,
                    detectedSourceLanguage: detected
                )
                AppLog.info(.engine, "idioma detectado localmente (NL): \(detected)")
            }
            storeCache(key, value: outcome)
            AppLog.info(
                .engine,
                "provider OK em \(ms)ms — outChars=\(outcome.text.count), detected=\(outcome.detectedSourceLanguage ?? "nil")"
            )
            return outcome
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            AppLog.error(
                .engine,
                "provider '\(provider.displayName)' falhou após \(ms)ms: \(error.localizedDescription) | \(String(describing: error))"
            )
            throw error
        }
    }

    private func clearCache() {
        cacheOrder.removeAll(keepingCapacity: true)
        cacheValues.removeAll(keepingCapacity: true)
    }

    private func touchCache(_ key: CacheKey) {
        if let index = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: index)
        }
        cacheOrder.append(key)
    }

    private func storeCache(_ key: CacheKey, value: TranslationOutcome) {
        if cacheValues[key] == nil {
            cacheOrder.append(key)
        } else {
            touchCache(key)
        }
        cacheValues[key] = value
        while cacheOrder.count > Self.maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cacheValues.removeValue(forKey: evicted)
        }
    }

    private func makeProvider() -> TranslationProvider {
        switch settings.providerKind {
        case .apple:
            if #available(macOS 15.0, *) {
                return AppleTranslationProvider(bridge: appleBridge)
            }
            AppLog.warning(.engine, "Apple Translation indisponível — requer macOS 15+")
            return UnavailableProvider(
                id: ProviderKind.apple.rawValue,
                displayName: ProviderKind.apple.displayName,
                message: "Apple Translation requer macOS 15+"
            )
        case .deepl:
            return DeepLProvider(
                apiKey: KeychainStore.string(for: .deeplAPIKey) ?? "",
                useFreeAPI: settings.deeplUseFreeAPI
            )
        case .google:
            return GoogleTranslateProvider(
                apiKey: KeychainStore.string(for: .googleAPIKey) ?? ""
            )
        case .groq:
            return OpenAICompatibleProvider(
                kind: .groq,
                baseURL: ProviderKind.groq.openAICompatibleBaseURL ?? "",
                model: settings.groqModel,
                apiKey: KeychainStore.string(for: .groqAPIKey) ?? "",
                requiresAPIKey: true
            )
        case .gemini:
            return GeminiProvider(
                apiKey: KeychainStore.string(for: .geminiAPIKey) ?? "",
                model: settings.geminiModel
            )
        case .mistral:
            return OpenAICompatibleProvider(
                kind: .mistral,
                baseURL: ProviderKind.mistral.openAICompatibleBaseURL ?? "",
                model: settings.mistralModel,
                apiKey: KeychainStore.string(for: .mistralAPIKey) ?? "",
                requiresAPIKey: true
            )
        case .deepSeek:
            return OpenAICompatibleProvider(
                kind: .deepSeek,
                baseURL: ProviderKind.deepSeek.openAICompatibleBaseURL ?? "",
                model: settings.deepSeekModel,
                apiKey: KeychainStore.string(for: .deepSeekAPIKey) ?? "",
                requiresAPIKey: true
            )
        case .openRouter:
            return OpenAICompatibleProvider(
                kind: .openRouter,
                baseURL: ProviderKind.openRouter.openAICompatibleBaseURL ?? "",
                model: settings.openRouterModel,
                apiKey: KeychainStore.string(for: .openRouterAPIKey) ?? "",
                requiresAPIKey: true,
                extraHeaders: [
                    "HTTP-Referer": "https://prism.translate",
                    "X-Title": "Prism"
                ]
            )
        case .openAICompatible:
            return OpenAICompatibleProvider(
                kind: .openAICompatible,
                baseURL: settings.openAIBaseURL,
                model: settings.openAIModel,
                apiKey: KeychainStore.string(for: .openAIAPIKey) ?? "",
                requiresAPIKey: false
            )
        case .customHTTP:
            return CustomHTTPProvider(
                url: settings.customHTTPURL,
                method: settings.customHTTPMethod,
                headersJSON: settings.customHTTPHeadersJSON,
                bodyTemplate: settings.customHTTPBodyTemplate,
                responseJSONPath: settings.customHTTPResponsePath
            )
        }
    }
}

private struct UnavailableProvider: TranslationProvider {
    let id: String
    let displayName: String
    let message: String

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        AppLog.error(.engine, "provider indisponível: \(message)")
        throw TranslationError.providerUnavailable(message)
    }
}
