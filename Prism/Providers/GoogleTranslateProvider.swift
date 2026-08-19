import Foundation

struct GoogleTranslateProvider: TranslationProvider {
    let id = ProviderKind.google.rawValue
    let displayName = ProviderKind.google.displayName
    let apiKey: String

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        guard !apiKey.isEmpty else {
            AppLog.error(.google, "Google Translate: API key não configurada — abra Configurações › Provedor")
            throw TranslationError.invalidConfiguration(String(localized: "Set the Google API key in Settings"))
        }

        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            throw TranslationError.invalidConfiguration(String(localized: "Invalid Google URL"))
        }

        ProviderLog.sending(
            .google,
            engine: "Google Translate",
            endpoint: "translation.googleapis.com/language/translate/v2",
            chars: text.count,
            from: from,
            to: to
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = "q=\(formEncode(text))"
        body += "&target=\(formEncode(Self.apiCode(for: to)))"
        body += "&format=text"
        if let from, !from.isEmpty {
            body += "&source=\(formEncode(Self.apiCode(for: from)))"
        }
        request.httpBody = body.data(using: .utf8)

        let started = Date()
        let (raw, response) = try await URLSession.shared.data(for: request)
        let (http, data) = try ProviderLog.requireSuccess(
            data: raw,
            response: response,
            category: .google,
            engine: "Google Translate",
            since: started
        )

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
        ProviderLog.received(
            .google,
            engine: "Google Translate",
            status: http.statusCode,
            bytes: data.count,
            since: started,
            outChars: first.translatedText.count,
            detected: detected
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

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }
}
