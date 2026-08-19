import Foundation

@MainActor
final class TranslationEngine {
    private var settings: AppSettings
    private let appleBridge: AppleTranslationBridge

    private struct CacheKey: Hashable {
        let text: String
        let from: String?
        let to: String
        let engine: String
    }

    private struct CacheEntry {
        let outcome: TranslationOutcome
        let storedAt: Date
    }

    /// Small LRU of recent translations (same phrase re-translated instantly).
    private var cacheOrder: [CacheKey] = []
    private var cacheValues: [CacheKey: CacheEntry] = [:]
    private static let maxCacheEntries = 64
    private static let maxCacheableCharacters = 512
    private static let cacheTTL: TimeInterval = 5 * 60

    init(settings: AppSettings, appleBridge: AppleTranslationBridge) {
        self.settings = settings
        self.appleBridge = appleBridge
    }

    func updateSettings(_ settings: AppSettings) {
        let providerChanged = settings.providerKind != self.settings.providerKind
        let engineFingerprintChanged =
            settings.engineLogDescription != self.settings.engineLogDescription
        let languagesChanged =
            settings.incomingSourceLanguage != self.settings.incomingSourceLanguage
            || settings.incomingTargetLanguage != self.settings.incomingTargetLanguage
            || settings.outgoingSourceLanguage != self.settings.outgoingSourceLanguage
            || settings.outgoingTargetLanguage != self.settings.outgoingTargetLanguage
        let cacheSettingChanged = settings.cacheTranslations != self.settings.cacheTranslations
        self.settings = settings
        if providerChanged || engineFingerprintChanged || languagesChanged || cacheSettingChanged {
            AppLog.info(
                .engine,
                "Motor ou idiomas mudaram — cache de traduções limpo (agora: \(settings.engineLogDescription))"
            )
            clearCache()
        }
    }

    func clearCacheOnBackground() {
        let count = cacheValues.count
        guard count > 0 else { return }
        clearCache()
        AppLog.info(.engine, "Cache limpo ao perder foco (\(count) entradas)")
    }

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        let key = CacheKey(
            text: text,
            from: from,
            to: to,
            engine: settings.engineLogDescription
        )
        AppLog.info(
            .engine,
            "Pedido ao motor \(settings.engineLogDescription) — \(LanguageCode.pairLabel(from: from, to: to)), \(text.count) caracteres, cache \(cacheValues.count)/\(Self.maxCacheEntries)"
        )
        purgeExpiredCacheEntries()
        if let cached = cacheValues[key], !isExpired(cached) {
            touchCache(key)
            AppLog.info(
                .engine,
                "Cache: mesma frase já traduzida por este motor — reusando resultado (\(cached.outcome.text.count) caracteres, sem chamar a API)"
            )
            if from == nil, cached.outcome.detectedSourceLanguage == nil,
               let detected = LanguageDetector.detect(in: text)
            {
                let enriched = TranslationOutcome(
                    text: cached.outcome.text,
                    detectedSourceLanguage: detected
                )
                storeCache(key, value: enriched)
                AppLog.info(
                    .engine,
                    "Idioma de origem detectado no Mac (NL): \(LanguageCode.displayName(for: detected))"
                )
                return enriched
            }
            return cached.outcome
        }
        cacheValues.removeValue(forKey: key)

        let provider = makeProvider()
        AppLog.info(
            .engine,
            "Cache vazio — chamando \(provider.displayName)"
        )
        let started = Date()
        do {
            var outcome = try await provider.translate(text, from: from, to: to)
            if from == nil, outcome.detectedSourceLanguage == nil,
               let detected = LanguageDetector.detect(in: text)
            {
                outcome = TranslationOutcome(
                    text: outcome.text,
                    detectedSourceLanguage: detected
                )
                AppLog.info(
                    .engine,
                    "Idioma de origem detectado no Mac (NL): \(LanguageCode.displayName(for: detected))"
                )
            }
            storeCache(key, value: outcome)
            AppLog.info(
                .engine,
                "\(provider.displayName) concluiu em \(AppLog.duration(since: started)) — \(outcome.text.count) caracteres"
                    + (outcome.detectedSourceLanguage.map {
                        ", origem: \(LanguageCode.displayName(for: $0))"
                    } ?? "")
            )
            return outcome
        } catch {
            AppLog.error(
                .engine,
                "\(provider.displayName) falhou após \(AppLog.duration(since: started)): \(error.localizedDescription)"
            )
            throw error
        }
    }

    private func clearCache() {
        cacheOrder.removeAll(keepingCapacity: true)
        cacheValues.removeAll(keepingCapacity: true)
    }

    private func isExpired(_ entry: CacheEntry) -> Bool {
        Date().timeIntervalSince(entry.storedAt) > Self.cacheTTL
    }

    private func purgeExpiredCacheEntries() {
        let expired = cacheValues.filter { isExpired($0.value) }.map(\.key)
        for key in expired {
            cacheValues.removeValue(forKey: key)
            cacheOrder.removeAll { $0 == key }
        }
    }

    private func touchCache(_ key: CacheKey) {
        if let index = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: index)
        }
        cacheOrder.append(key)
    }

    private func storeCache(_ key: CacheKey, value: TranslationOutcome) {
        guard settings.cacheTranslations else { return }
        guard key.text.count <= Self.maxCacheableCharacters else { return }

        if cacheValues[key] == nil {
            cacheOrder.append(key)
        } else {
            touchCache(key)
        }
        cacheValues[key] = CacheEntry(outcome: value, storedAt: Date())
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
            AppLog.warning(
                .engine,
                "Apple Translation indisponível neste Mac — requer macOS 15 ou posterior"
            )
            return UnavailableProvider(
                id: ProviderKind.apple.rawValue,
                displayName: ProviderKind.apple.displayName,
                message: "Apple Translation requer macOS 15+"
            )
        case .deepl:
            return DeepLProvider(
                apiKey: SensitiveData(keychain: .deeplAPIKey) ?? SensitiveData(""),
                useFreeAPI: settings.deeplUseFreeAPI
            )
        case .google:
            return GoogleTranslateProvider(
                apiKey: SensitiveData(keychain: .googleAPIKey) ?? SensitiveData("")
            )
        case .openAICompatible:
            return OpenAICompatibleProvider(
                kind: .openAICompatible,
                baseURL: settings.openAIBaseURL,
                model: settings.openAIModel,
                apiKey: SensitiveData(keychain: .openAIAPIKey) ?? SensitiveData(""),
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
        AppLog.error(.engine, "Motor indisponível: \(message)")
        throw TranslationError.providerUnavailable(message)
    }
}

extension TranslationEngine {
    var testingCacheCount: Int { cacheValues.count }

    func testingSeedCache(
        text: String,
        outcome: TranslationOutcome,
        from: String? = nil,
        to: String = "pt"
    ) {
        let key = CacheKey(
            text: text,
            from: from,
            to: to,
            engine: settings.engineLogDescription
        )
        storeCache(key, value: outcome)
    }
}
