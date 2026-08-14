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
        let normalized = normalize(id)
        return commonTargets.first(where: { $0.id == normalized })?.displayName
            ?? Locale.current.localizedString(forLanguageCode: normalized)
            ?? id
    }

    /// Ex.: "detecção automática → English" ou "Português → English".
    static func pairLabel(from: String?, to: String) -> String {
        let source = from.map { displayName(for: $0) } ?? "detecção automática"
        return "\(source) → \(displayName(for: to))"
    }

    /// Maps provider codes (EN, PT-BR, zh-CN, …) onto app language ids when possible.
    static func normalize(_ code: String) -> String {
        let lower = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: "-")
        switch lower {
        case "en", "en-us", "en-gb": return "en"
        case "pt", "pt-br", "pt-pt": return "pt"
        case "zh", "zh-cn", "zh-hans", "zh-hans-cn": return "zh-Hans"
        case "zh-tw", "zh-hk", "zh-hant", "zh-hant-tw": return "zh-Hant"
        default:
            if commonTargets.contains(where: { $0.id == lower }) { return lower }
            let base = Locale(identifier: lower).language.languageCode?.identifier ?? lower
            if commonTargets.contains(where: { $0.id == base }) { return base }
            return lower
        }
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
