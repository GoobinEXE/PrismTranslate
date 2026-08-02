import Foundation

struct LanguageCode: Identifiable, Hashable {
    let id: String
    let displayName: String

    static let commonTargets: [LanguageCode] = [
        .init(id: "en", displayName: "English"),
        .init(id: "pt", displayName: "Português"),
        .init(id: "es", displayName: "Español"),
        .init(id: "fr", displayName: "Français"),
        .init(id: "de", displayName: "Deutsch"),
        .init(id: "it", displayName: "Italiano"),
        .init(id: "ja", displayName: "日本語"),
        .init(id: "ko", displayName: "한국어"),
        .init(id: "zh-Hans", displayName: "中文 (简体)"),
        .init(id: "zh-Hant", displayName: "中文 (繁體)"),
        .init(id: "ru", displayName: "Русский"),
        .init(id: "ar", displayName: "العربية"),
        .init(id: "nl", displayName: "Nederlands"),
        .init(id: "pl", displayName: "Polski"),
        .init(id: "tr", displayName: "Türkçe"),
        .init(id: "hi", displayName: "हिन्दी")
    ]

    static func displayName(for id: String) -> String {
        commonTargets.first(where: { $0.id == id })?.displayName ?? id
    }

    /// Idioma preferido do sistema, mapeado para um código suportado pelo app.
    static var systemLanguage: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        if commonTargets.contains(where: { $0.id == code }) {
            return code
        }
        // Map regional variants
        if code == "zh" {
            return preferred.lowercased().contains("hant") || preferred.lowercased().contains("tw")
                ? "zh-Hant" : "zh-Hans"
        }
        return "en"
    }

    /// Destino padrão: inglês (ou português se o sistema já for inglês), para não coincidir com a origem.
    static var systemDefaultTarget: String {
        systemLanguage == "en" ? "pt" : "en"
    }
}
