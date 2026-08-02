import Foundation
import os

@MainActor
final class TranslationEngine {
    private static let logger = Logger(subsystem: "com.quicktranslate", category: "Engine")
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
    private var cacheValues: [CacheKey: String] = [:]
    private static let maxCacheEntries = 64

    init(settings: AppSettings, appleBridge: AppleTranslationBridge) {
        self.settings = settings
        self.appleBridge = appleBridge
    }

    func updateSettings(_ settings: AppSettings) {
        let providerChanged = settings.providerKind != self.settings.providerKind
        let languagesChanged =
            settings.resolvedSourceLanguage != self.settings.resolvedSourceLanguage
            || settings.targetLanguage != self.settings.targetLanguage
        self.settings = settings
        if providerChanged || languagesChanged {
            clearCache()
        }
    }

    func translate(_ text: String, from: String?, to: String) async throws -> String {
        let key = CacheKey(
            text: text,
            from: from,
            to: to,
            provider: settings.providerKind.rawValue
        )
        if let cached = cacheValues[key] {
            touchCache(key)
            Self.logger.info("⚡ [Cache] tradução retornada do cache em memória (sem chamar API)")
            return cached
        }

        let provider = makeProvider()
        Self.logger.info("🚀 executando tradução via '\(provider.displayName, privacy: .public)'")
        let translated = try await provider.translate(text, from: from, to: to)
        storeCache(key, value: translated)
        return translated
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

    private func storeCache(_ key: CacheKey, value: String) {
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
                baseURL: settings.openAIBaseURL,
                model: settings.openAIModel,
                apiKey: KeychainStore.string(for: .openAIAPIKey) ?? ""
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

    func translate(_ text: String, from: String?, to: String) async throws -> String {
        throw TranslationError.providerUnavailable(message)
    }
}
