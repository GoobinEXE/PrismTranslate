import Foundation
import ServiceManagement

struct AppSettings: Equatable {
    var isEnabled: Bool = true
    var enterTranslatesAndSends: Bool = false
    var targetLanguage: String = LanguageCode.systemDefaultTarget
    /// nil = detecção automática; padrão = idioma do sistema.
    var sourceLanguage: String? = LanguageCode.systemLanguage
    var providerKind: ProviderKind = .apple
    var openAtLogin: Bool = false

    /// ⌃⌥T by default — avoids ⌘ conflicts with browsers and system apps.
    var translateOnlyHotkey: HotkeyChord = .translateOnlyDefault
    /// ⌃⌥⏎ by default — avoids ⌥⏎ (newline / IDE quick-fix).
    var translateAndSendHotkey: HotkeyChord = .translateAndSendDefault

    // DeepL
    var deeplUseFreeAPI: Bool = true

    // OpenAI-compatible / LM Studio
    var openAIBaseURL: String = "http://localhost:1234/v1"
    var openAIModel: String = "local-model"

    // Custom HTTP
    var customHTTPURL: String = "http://localhost:8080/translate"
    var customHTTPMethod: String = "POST"
    var customHTTPHeadersJSON: String = #"{"Content-Type":"application/json"}"#
    var customHTTPBodyTemplate: String = #"{"text":"{{text}}","target":"{{to}}","source":"{{from}}"}"#
    var customHTTPResponsePath: String = "translatedText"

    /// Source language to send to providers; nil (auto) when unset or empty.
    var resolvedSourceLanguage: String? {
        guard let sourceLanguage, !sourceLanguage.isEmpty else { return nil }
        return sourceLanguage
    }

    private static let defaultsKey = "AppSettings"
    private static let migratedSourceToSystemKey = "didMigrateSourceLanguageToSystem"

    mutating func resetHotkeysToDefaults() {
        translateOnlyHotkey = .translateOnlyDefault
        translateAndSendHotkey = .translateAndSendDefault
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
        return migrateSourceLanguageIfNeeded(settings)
    }

    /// One-time: old default was `nil` (auto). Switch to the system language once,
    /// without overriding a later explicit choice of “Automático”.
    private static func migrateSourceLanguageIfNeeded(_ settings: AppSettings) -> AppSettings {
        guard !UserDefaults.standard.bool(forKey: migratedSourceToSystemKey) else {
            return settings
        }
        var migrated = settings
        if migrated.sourceLanguage == nil {
            migrated.sourceLanguage = LanguageCode.systemLanguage
            // Avoid source == target after migration (old target often matched system language).
            if migrated.targetLanguage == migrated.sourceLanguage {
                migrated.targetLanguage = LanguageCode.systemDefaultTarget
            }
            migrated.save()
        }
        UserDefaults.standard.set(true, forKey: migratedSourceToSystemKey)
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
    var targetLanguage: String
    var sourceLanguage: String?
    var providerKind: ProviderKind
    var openAtLogin: Bool
    var translateOnlyHotkey: HotkeyChord?
    var translateAndSendHotkey: HotkeyChord?
    var deeplUseFreeAPI: Bool
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
        targetLanguage = settings.targetLanguage
        sourceLanguage = settings.sourceLanguage
        providerKind = settings.providerKind
        openAtLogin = settings.openAtLogin
        translateOnlyHotkey = settings.translateOnlyHotkey
        translateAndSendHotkey = settings.translateAndSendHotkey
        deeplUseFreeAPI = settings.deeplUseFreeAPI
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
        s.targetLanguage = targetLanguage
        s.sourceLanguage = sourceLanguage
        s.providerKind = providerKind
        s.openAtLogin = openAtLogin
        s.translateOnlyHotkey = translateOnlyHotkey ?? .translateOnlyDefault
        s.translateAndSendHotkey = translateAndSendHotkey ?? .translateAndSendDefault
        s.deeplUseFreeAPI = deeplUseFreeAPI
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
