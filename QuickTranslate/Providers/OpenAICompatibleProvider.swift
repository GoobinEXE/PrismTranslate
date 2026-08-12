import Foundation

struct OpenAICompatibleProvider: TranslationProvider {
    let id = ProviderKind.openAICompatible.rawValue
    let displayName = ProviderKind.openAICompatible.displayName
    let baseURL: String
    let model: String
    let apiKey: String

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty, !model.isEmpty else {
            throw TranslationError.invalidConfiguration("Configure base URL e modelo OpenAI-compatible")
        }

        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            throw TranslationError.invalidConfiguration("Base URL inválida")
        }

        AppLog.info(
            .openAI,
            "📡 [OpenAI-compatible] POST \(url.absoluteString) — model=\(model), chars=\(text.count), from=\(from ?? "auto"), to=\(to), keyConfigured=\(!apiKey.isEmpty)"
        )

        let targetName = LanguageCode.displayName(for: to)
        let sourceHint = from.map { LanguageCode.displayName(for: $0) } ?? "auto-detect"
        let system = """
        You are a translation engine. Translate the user message into \(targetName) (source: \(sourceHint)).
        Return ONLY the translated text. No quotes, no explanations.
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            AppLog.error(.openAI, "❌ [OpenAI-compatible] HTTP \(http.statusCode): \(bodyText)")
            throw TranslationError.httpStatus(http.statusCode, bodyText)
        }

        let content = try Self.parseChatContent(from: data)
        return TranslationOutcome(text: content)
    }

    /// Parses a chat/completions response and returns the first choice's trimmed content.
    /// Internal (not private) so unit tests can exercise the parsing directly.
    static func parseChatContent(from data: Data) throws -> String {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return content
    }
}
