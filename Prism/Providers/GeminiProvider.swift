import Foundation

/// Google AI Studio / Gemini generateContent API (free tier via API key).
struct GeminiProvider: TranslationProvider {
    let id = ProviderKind.gemini.rawValue
    let displayName = ProviderKind.gemini.displayName
    let apiKey: String
    let model: String

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            AppLog.error(.gemini, "Gemini: API key não configurada — abra Configurações › Provedor")
            throw TranslationError.invalidConfiguration(
                "Configure a API key do Gemini (Google AI Studio) nas Configurações"
            )
        }
        guard !trimmedModel.isEmpty else {
            throw TranslationError.invalidConfiguration("Configure o modelo Gemini")
        }

        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(trimmedModel):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: trimmedKey)]
        guard let url = components?.url else {
            throw TranslationError.invalidConfiguration("URL Gemini inválida")
        }

        ProviderLog.sending(
            .gemini,
            engine: "Gemini",
            endpoint: "generativelanguage.googleapis.com/v1beta/models/\(trimmedModel):generateContent",
            chars: text.count,
            from: from,
            to: to,
            model: trimmedModel
        )

        let prompt = AITranslationPrompt.make(text: text, from: from, to: to)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")

        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": prompt.system]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt.user]]
                ]
            ],
            "generationConfig": [
                "temperature": 0
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            ProviderLog.failed(.gemini, engine: "Gemini", status: nil, since: started, body: "")
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            ProviderLog.failed(
                .gemini,
                engine: "Gemini",
                status: http.statusCode,
                since: started,
                body: bodyText
            )
            throw TranslationError.httpStatus(http.statusCode, bodyText)
        }

        let content = try Self.parseGenerateContent(from: data)
        ProviderLog.received(
            .gemini,
            engine: "Gemini",
            status: http.statusCode,
            bytes: data.count,
            since: started,
            outChars: content.count
        )
        return TranslationOutcome(text: content)
    }

    /// Parses generateContent JSON and returns the first candidate text part.
    static func parseGenerateContent(from data: Data) throws -> String {
        struct GenerateResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        let text = decoded.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return text
    }
}
