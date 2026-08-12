import Foundation

struct GoogleTranslateProvider: TranslationProvider {
    let id = ProviderKind.google.rawValue
    let displayName = ProviderKind.google.displayName
    let apiKey: String

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        guard !apiKey.isEmpty else {
            throw TranslationError.invalidConfiguration("Configure a API key do Google nas Preferências")
        }

        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "target", value: Self.apiCode(for: to)),
            URLQueryItem(name: "format", value: "text")
        ]
        if let from, !from.isEmpty {
            query.append(URLQueryItem(name: "source", value: Self.apiCode(for: from)))
        }
        components.queryItems = query

        guard let url = components.url else {
            throw TranslationError.invalidConfiguration("URL Google inválida")
        }

        AppLog.info(
            .google,
            "📡 [Google] POST translation.googleapis.com — chars=\(text.count), from=\(from ?? "auto"), to=\(to), keyConfigured=\(!apiKey.isEmpty)"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            AppLog.error(.google, "❌ [Google] HTTP \(http.statusCode): \(bodyText)")
            throw TranslationError.httpStatus(http.statusCode, bodyText)
        }

        struct GoogleResponse: Decodable {
            struct DataBlock: Decodable {
                struct Translation: Decodable {
                    let translatedText: String
                    let detectedSourceLanguage: String?
                }
                let translations: [Translation]
            }
            let data: DataBlock
        }

        let decoded = try JSONDecoder().decode(GoogleResponse.self, from: data)
        guard let first = decoded.data.translations.first else {
            throw TranslationError.emptyResponse
        }
        let detected = first.detectedSourceLanguage.map { LanguageCode.normalize($0) }
        AppLog.info(
            .google,
            "✅ [Google] HTTP \(http.statusCode) OK — \(first.translatedText.count) chars, detected=\(detected ?? "nil")"
        )
        return TranslationOutcome(text: first.translatedText, detectedSourceLanguage: detected)
    }

    /// Internal (not private) so unit tests can exercise the mapping directly.
    static func apiCode(for code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return code
        }
    }
}
