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
        let engineFingerprintChanged =
            settings.engineLogDescription != self.settings.engineLogDescription
        let languagesChanged =
            settings.incomingSourceLanguage != self.settings.incomingSourceLanguage
            || settings.incomingTargetLanguage != self.settings.incomingTargetLanguage
            || settings.outgoingSourceLanguage != self.settings.outgoingSourceLanguage
            || settings.outgoingTargetLanguage != self.settings.outgoingTargetLanguage
        self.settings = settings
        if providerChanged || engineFingerprintChanged || languagesChanged {
            AppLog.info(
                .engine,
                "Motor ou idiomas mudaram — cache de traduções limpo (agora: \(settings.engineLogDescription))"
            )
            clearCache()
        }
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
        if let cached = cacheValues[key] {
            touchCache(key)
            AppLog.info(
                .engine,
                "Cache: mesma frase já traduzida por este motor — reusando resultado (\(cached.text.count) caracteres, sem chamar a API)"
            )
            if from == nil, cached.detectedSourceLanguage == nil,
               let detected = LanguageDetector.detect(in: text)
            {
                let enriched = TranslationOutcome(
                    text: cached.text,
                    detectedSourceLanguage: detected
                )
                storeCache(key, value: enriched)
                AppLog.info(
                    .engine,
                    "Idioma de origem detectado no Mac (NL): \(LanguageCode.displayName(for: detected))"
                )
                return enriched
            }
            return cached
        }

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
                apiKey: KeychainStore.string(for: .deeplAPIKey) ?? "",
                useFreeAPI: settings.deeplUseFreeAPI
            )
        case .google:
            return GoogleTranslateProvider(
                apiKey: KeychainStore.string(for: .googleAPIKey) ?? ""
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
        AppLog.error(.engine, "Motor indisponível: \(message)")
        throw TranslationError.providerUnavailable(message)
    }
}
