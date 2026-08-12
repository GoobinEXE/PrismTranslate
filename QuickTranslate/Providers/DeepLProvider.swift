import Foundation

struct DeepLProvider: TranslationProvider {
    let id = ProviderKind.deepl.rawValue
    let displayName = ProviderKind.deepl.displayName
    let apiKey: String
    let useFreeAPI: Bool

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        guard !apiKey.isEmpty else {
            throw TranslationError.invalidConfiguration("Configure a API key do DeepL nas Configurações")
        }

        let host = useFreeAPI ? "api-free.deepl.com" : "api.deepl.com"
        guard let url = URL(string: "https://\(host)/v2/translate") else {
            throw TranslationError.invalidConfiguration("URL DeepL inválida")
        }

        AppLog.info(
            .deepl,
            "📡 [DeepL] POST https://\(host)/v2/translate — chars=\(text.count), from=\(from ?? "auto"), to=\(to), freeAPI=\(useFreeAPI), keyConfigured=\(!apiKey.isEmpty)"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = "text=\(formEncode(text))"
        body += "&target_lang=\(formEncode(Self.apiCode(for: to, isTarget: true)))"
        if let from, !from.isEmpty {
            body += "&source_lang=\(formEncode(Self.apiCode(for: from, isTarget: false)))"
        }
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            AppLog.error(.deepl, "❌ [DeepL] HTTP \(http.statusCode): \(bodyText)")
            throw TranslationError.httpStatus(http.statusCode, bodyText)
        }

        struct DeepLResponse: Decodable {
            struct Translation: Decodable {
                let text: String
                let detectedSourceLanguage: String?

                enum CodingKeys: String, CodingKey {
                    case text
                    case detectedSourceLanguage = "detected_source_language"
                }
            }
            let translations: [Translation]
        }

        let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)
        guard let first = decoded.translations.first else {
            throw TranslationError.emptyResponse
        }
        AppLog.info(.deepl, "✅ [DeepL] resposta HTTP \(http.statusCode) OK (\(first.text.count) chars)")
        let detected = first.detectedSourceLanguage.map { LanguageCode.normalize($0) }
        return TranslationOutcome(text: first.text, detectedSourceLanguage: detected)
    }

    /// Maps app language codes to DeepL codes. `target_lang` accepts regional variants
    /// (ZH-HANS/ZH-HANT, PT-BR/PT-PT) while `source_lang` only accepts the base language
    /// (ZH, PT) — hence the `isTarget` distinction.
    /// Internal (not private) so unit tests can exercise the mapping directly.
    static func apiCode(for code: String, isTarget: Bool) -> String {
        switch code.lowercased() {
        case "en": return "EN"
        case "pt", "pt-br": return isTarget ? "PT-BR" : "PT"
        case "pt-pt": return isTarget ? "PT-PT" : "PT"
        case "zh", "zh-cn", "zh-hans": return isTarget ? "ZH-HANS" : "ZH"
        case "zh-hant", "zh-tw": return isTarget ? "ZH-HANT" : "ZH"
        default: return code.uppercased()
        }
    }

    /// application/x-www-form-urlencoded — must escape `&`, `=`, `+`, spaces, etc.
    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }
}
