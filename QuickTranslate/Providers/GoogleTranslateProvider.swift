import Foundation
import os

struct GoogleTranslateProvider: TranslationProvider {
    private static let logger = Logger(subsystem: "com.quicktranslate", category: "GoogleTranslateProvider")

    let id = ProviderKind.google.rawValue
    let displayName = ProviderKind.google.displayName
    let apiKey: String

    func translate(_ text: String, from: String?, to: String) async throws -> String {
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

        Self.logger.info("📡 [Google] enviando requisição HTTP POST para translation.googleapis.com")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            Self.logger.error("❌ [Google] HTTP \(http.statusCode): \(bodyText, privacy: .public)")
            throw TranslationError.httpStatus(http.statusCode, bodyText)
        }

        struct GoogleResponse: Decodable {
            struct DataBlock: Decodable {
                struct Translation: Decodable {
                    let translatedText: String
                }
                let translations: [Translation]
            }
            let data: DataBlock
        }

        let decoded = try JSONDecoder().decode(GoogleResponse.self, from: data)
        guard let first = decoded.data.translations.first?.translatedText else {
            throw TranslationError.emptyResponse
        }
        return first
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
