import Foundation

struct OpenAICompatibleProvider: TranslationProvider {
    let kind: ProviderKind
    let baseURL: String
    let model: String
    let apiKey: String
    /// When true, empty API key fails fast with a configuration error.
    let requiresAPIKey: Bool
    let extraHeaders: [String: String]

    var id: String { kind.rawValue }
    var displayName: String { kind.displayName }

    init(
        kind: ProviderKind = .openAICompatible,
        baseURL: String,
        model: String,
        apiKey: String,
        requiresAPIKey: Bool = false,
        extraHeaders: [String: String] = [:]
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.requiresAPIKey = requiresAPIKey
        self.extraHeaders = extraHeaders
    }

    private var logCategory: AppLogCategory {
        switch kind {
        case .groq: return .groq
        case .mistral: return .mistral
        case .deepSeek: return .deepSeek
        case .openRouter: return .openRouter
        default: return .openAI
        }
    }

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, !trimmedModel.isEmpty else {
            throw TranslationError.invalidConfiguration(
                "Configure base URL e modelo para \(displayName)"
            )
        }
        if requiresAPIKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TranslationError.invalidConfiguration(
                "Configure a API key de \(displayName) nas Configurações"
            )
        }

        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            throw TranslationError.invalidConfiguration("Base URL inválida")
        }

        AppLog.info(
            logCategory,
            "📡 [\(displayName)] POST \(url.absoluteString) — model=\(trimmedModel), chars=\(text.count), from=\(from ?? "auto"), to=\(to), keyConfigured=\(!apiKey.isEmpty)"
        )

        let prompt = AITranslationPrompt.make(text: text, from: from, to: to)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let payload: [String: Any] = [
            "model": trimmedModel,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            AppLog.error(logCategory, "❌ [\(displayName)] HTTP \(http.statusCode): \(bodyText)")
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
