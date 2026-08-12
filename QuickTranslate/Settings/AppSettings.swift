import Foundation
import ServiceManagement

struct AppSettings: Equatable {
    var isEnabled: Bool = true
    var enterTranslatesAndSends: Bool = false

    // MARK: Idiomas — mensagens recebidas (só leitura / popup de leitura)

    /// nil = detecção automática.
    var incomingSourceLanguage: String? = nil
    /// Idioma para o qual traduzir o que você lê (padrão = idioma do sistema).
    var incomingTargetLanguage: String = LanguageCode.systemLanguage

    // MARK: Idiomas — suas mensagens (campo editável / replace)

    /// nil = detecção automática; padrão = idioma do sistema.
    var outgoingSourceLanguage: String? = LanguageCode.systemLanguage
    /// Idioma para o qual traduzir o que você escreve (padrão = inglês, ou pt se o sistema for en).
    var outgoingTargetLanguage: String = LanguageCode.systemDefaultTarget

    var providerKind: ProviderKind = .apple
    var openAtLogin: Bool = false

    /// ⌃⌥T by default — avoids ⌘ conflicts with browsers and system apps.
    var translateOnlyHotkey: HotkeyChord = .translateOnlyDefault
    /// ⌃⌥⏎ by default — avoids ⌥⏎ (newline / IDE quick-fix).
    var translateAndSendHotkey: HotkeyChord = .translateAndSendDefault
    /// Dedicated popup mode (selection → panel). Off by default (opt-in).
    var popupModeEnabled: Bool = false
    /// ⌃⌥Y by default — show translation popup.
    var popupHotkey: HotkeyChord = .popupDefault

    // DeepL
    var deeplUseFreeAPI: Bool = true

    // Free AI engines (API key in Keychain)
    var groqModel: String = ProviderKind.groq.defaultModel ?? "llama-3.1-8b-instant"
    var geminiModel: String = ProviderKind.gemini.defaultModel ?? "gemini-2.5-flash"
    var mistralModel: String = ProviderKind.mistral.defaultModel ?? "mistral-small-latest"
    var deepSeekModel: String = ProviderKind.deepSeek.defaultModel ?? "deepseek-v4-flash"
    var openRouterModel: String = ProviderKind.openRouter.defaultModel ?? "openrouter/free"

    // OpenAI-compatible / LM Studio
    var openAIBaseURL: String = "http://localhost:1234/v1"
    var openAIModel: String = "local-model"

    // Custom HTTP
    var customHTTPURL: String = "http://localhost:8080/translate"
    var customHTTPMethod: String = "POST"
    var customHTTPHeadersJSON: String = #"{"Content-Type":"application/json"}"#
    var customHTTPBodyTemplate: String = #"{"text":"{{text}}","target":"{{to}}","source":"{{from}}"}"#
    var customHTTPResponsePath: String = "translatedText"

    /// Source to send to providers for a direction; nil means auto-detect.
    func resolvedSourceLanguage(outgoing: Bool) -> String? {
        let raw = outgoing ? outgoingSourceLanguage : incomingSourceLanguage
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    func targetLanguage(outgoing: Bool) -> String {
        outgoing ? outgoingTargetLanguage : incomingTargetLanguage
    }

    /// Convenience for call sites that still think in “your messages” terms.
    var resolvedOutgoingSourceLanguage: String? {
        resolvedSourceLanguage(outgoing: true)
    }

    private static let defaultsKey = "AppSettings"
    private static let migratedSourceToSystemKey = "didMigrateSourceLanguageToSystem"
    private static let migratedDualLanguageKey = "didMigrateDualLanguagePairs"

    mutating func resetHotkeysToDefaults() {
        translateOnlyHotkey = .translateOnlyDefault
        translateAndSendHotkey = .translateAndSendDefault
        popupHotkey = .popupDefault
    }

    func save() {
        if let data = try? JSONEncoder().encode(CodableSettings(self)) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        Self.applyLoginItem(openAtLogin)
    }

    static func load() -> AppSettings {
        let settings: AppSettings
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(CodableSettings.self, from: data) {
            settings = decoded.asSettings()
        } else {
            settings = AppSettings()
        }
        return migrateDualLanguageIfNeeded(migrateSourceLanguageIfNeeded(settings))
    }

    /// One-time: old default was `nil` (auto). Switch outgoing source to the system language once.
    private static func migrateSourceLanguageIfNeeded(_ settings: AppSettings) -> AppSettings {
        guard !UserDefaults.standard.bool(forKey: migratedSourceToSystemKey) else {
            return settings
        }
        var migrated = settings
        if migrated.outgoingSourceLanguage == nil {
            migrated.outgoingSourceLanguage = LanguageCode.systemLanguage
            if migrated.outgoingTargetLanguage == migrated.outgoingSourceLanguage {
                migrated.outgoingTargetLanguage = LanguageCode.systemDefaultTarget
            }
            migrated.save()
        }
        UserDefaults.standard.set(true, forKey: migratedSourceToSystemKey)
        return migrated
    }

    /// One-time: seed incoming pair if this install only had a single source/target.
    private static func migrateDualLanguageIfNeeded(_ settings: AppSettings) -> AppSettings {
        guard !UserDefaults.standard.bool(forKey: migratedDualLanguageKey) else {
            return settings
        }
        var migrated = settings
        // Incoming defaults: detect → your language (typical “reading foreign chat”).
        if migrated.incomingTargetLanguage.isEmpty {
            migrated.incomingTargetLanguage = LanguageCode.systemLanguage
        }
        if migrated.incomingTargetLanguage == migrated.outgoingTargetLanguage,
           migrated.incomingSourceLanguage == nil,
           migrated.outgoingSourceLanguage != nil {
            // Keep outgoing as configured; incoming stays detect → system.
            migrated.incomingTargetLanguage = LanguageCode.systemLanguage
        }
        migrated.save()
        UserDefaults.standard.set(true, forKey: migratedDualLanguageKey)
        return migrated
    }

    static func applyLoginItem(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Best-effort; ignore registration errors in v1.
            }
        }
    }
}

private struct CodableSettings: Codable {
    var isEnabled: Bool
    var enterTranslatesAndSends: Bool
    /// Legacy single-pair keys (pre dual-language).
    var targetLanguage: String?
    var sourceLanguage: String?
    var incomingSourceLanguage: String?
    var incomingTargetLanguage: String?
    var outgoingSourceLanguage: String?
    var outgoingTargetLanguage: String?
    var providerKind: ProviderKind
    var openAtLogin: Bool
    var translateOnlyHotkey: HotkeyChord?
    var translateAndSendHotkey: HotkeyChord?
    var popupModeEnabled: Bool?
    var popupHotkey: HotkeyChord?
    var deeplUseFreeAPI: Bool
    var groqModel: String?
    var geminiModel: String?
    var mistralModel: String?
    var deepSeekModel: String?
    var openRouterModel: String?
    var openAIBaseURL: String
    var openAIModel: String
    var customHTTPURL: String
    var customHTTPMethod: String
    var customHTTPHeadersJSON: String
    var customHTTPBodyTemplate: String
    var customHTTPResponsePath: String

    init(_ settings: AppSettings) {
        isEnabled = settings.isEnabled
        enterTranslatesAndSends = settings.enterTranslatesAndSends
        // Keep legacy keys in sync with outgoing for older builds / tooling.
        targetLanguage = settings.outgoingTargetLanguage
        sourceLanguage = settings.outgoingSourceLanguage
        incomingSourceLanguage = settings.incomingSourceLanguage
        incomingTargetLanguage = settings.incomingTargetLanguage
        outgoingSourceLanguage = settings.outgoingSourceLanguage
        outgoingTargetLanguage = settings.outgoingTargetLanguage
        providerKind = settings.providerKind
        openAtLogin = settings.openAtLogin
        translateOnlyHotkey = settings.translateOnlyHotkey
        translateAndSendHotkey = settings.translateAndSendHotkey
        popupModeEnabled = settings.popupModeEnabled
        popupHotkey = settings.popupHotkey
        deeplUseFreeAPI = settings.deeplUseFreeAPI
        groqModel = settings.groqModel
        geminiModel = settings.geminiModel
        mistralModel = settings.mistralModel
        deepSeekModel = settings.deepSeekModel
        openRouterModel = settings.openRouterModel
        openAIBaseURL = settings.openAIBaseURL
        openAIModel = settings.openAIModel
        customHTTPURL = settings.customHTTPURL
        customHTTPMethod = settings.customHTTPMethod
        customHTTPHeadersJSON = settings.customHTTPHeadersJSON
        customHTTPBodyTemplate = settings.customHTTPBodyTemplate
        customHTTPResponsePath = settings.customHTTPResponsePath
    }

    func asSettings() -> AppSettings {
        var s = AppSettings()
        s.isEnabled = isEnabled
        s.enterTranslatesAndSends = enterTranslatesAndSends

        let legacySource = sourceLanguage
        let legacyTarget = targetLanguage ?? LanguageCode.systemDefaultTarget
        let hasDual =
            outgoingTargetLanguage != nil
            || incomingTargetLanguage != nil
            || outgoingSourceLanguage != nil
            || incomingSourceLanguage != nil

        if hasDual {
            s.outgoingTargetLanguage = outgoingTargetLanguage ?? legacyTarget
            // Explicit null means “Detectar idioma” — do not fall back to legacy.
            s.outgoingSourceLanguage = outgoingSourceLanguage
            s.incomingTargetLanguage = incomingTargetLanguage ?? LanguageCode.systemLanguage
            s.incomingSourceLanguage = incomingSourceLanguage
        } else {
            s.outgoingTargetLanguage = legacyTarget
            s.outgoingSourceLanguage = legacySource ?? LanguageCode.systemLanguage
            s.incomingTargetLanguage = LanguageCode.systemLanguage
            s.incomingSourceLanguage = nil
        }

        s.providerKind = providerKind
        s.openAtLogin = openAtLogin
        s.translateOnlyHotkey = translateOnlyHotkey ?? .translateOnlyDefault
        s.translateAndSendHotkey = translateAndSendHotkey ?? .translateAndSendDefault
        s.popupModeEnabled = popupModeEnabled ?? false
        s.popupHotkey = popupHotkey ?? .popupDefault
        s.deeplUseFreeAPI = deeplUseFreeAPI
        s.groqModel = groqModel ?? ProviderKind.groq.defaultModel ?? s.groqModel
        s.geminiModel = geminiModel ?? ProviderKind.gemini.defaultModel ?? s.geminiModel
        s.mistralModel = mistralModel ?? ProviderKind.mistral.defaultModel ?? s.mistralModel
        s.deepSeekModel = deepSeekModel ?? ProviderKind.deepSeek.defaultModel ?? s.deepSeekModel
        s.openRouterModel = openRouterModel ?? ProviderKind.openRouter.defaultModel ?? s.openRouterModel
        s.openAIBaseURL = openAIBaseURL
        s.openAIModel = openAIModel
        s.customHTTPURL = customHTTPURL
        s.customHTTPMethod = customHTTPMethod
        s.customHTTPHeadersJSON = customHTTPHeadersJSON
        s.customHTTPBodyTemplate = customHTTPBodyTemplate
        s.customHTTPResponsePath = customHTTPResponsePath
        return s
    }
}
