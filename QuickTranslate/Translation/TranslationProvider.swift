import Foundation

/// Result of a translation call, including optional API-detected source language.
struct TranslationOutcome: Equatable {
    let text: String
    /// App-style language code when the provider reported detection (e.g. auto source).
    let detectedSourceLanguage: String?

    init(text: String, detectedSourceLanguage: String? = nil) {
        self.text = text
        self.detectedSourceLanguage = detectedSourceLanguage
    }
}

protocol TranslationProvider {
    var id: String { get }
    var displayName: String { get }
    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome
}

enum TranslationError: LocalizedError {
    case providerUnavailable(String)
    case invalidConfiguration(String)
    case emptyResponse
    case httpStatus(Int, String)
    case appleTranslationFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let name):
            return "Provedor indisponível: \(name)"
        case .invalidConfiguration(let message):
            return message
        case .emptyResponse:
            return "Resposta vazia do provedor"
        case .httpStatus(let code, let body):
            return Self.userFacingHTTPMessage(statusCode: code, body: body)
        case .appleTranslationFailed(let message):
            return "Apple Translation: \(message)"
        }
    }

    /// Maps provider HTTP failures (DeepSeek 402, OpenAI quota, 401/429, etc.) to short PT copy.
    static func userFacingHTTPMessage(statusCode: Int, body: String) -> String {
        switch classifyHTTPFailure(statusCode: statusCode, body: body) {
        case .billingOrQuota:
            return "Saldo ou cota da API esgotados. Recarregue créditos no provedor ou troque o motor nas Configurações."
        case .unauthorized:
            return "API key inválida ou sem permissão. Verifique a chave nas Configurações."
        case .rateLimited:
            return "Limite de requisições atingido. Aguarde um momento e tente de novo."
        case .modelUnavailable:
            return "Modelo da API indisponível ou descontinuado. Atualize o modelo nas Configurações."
        case .serverError:
            return "O provedor está indisponível (HTTP \(statusCode)). Tente novamente em instantes."
        case .other:
            if let apiMessage = extractAPIErrorMessage(from: body), !apiMessage.isEmpty {
                return "Erro do provedor (HTTP \(statusCode)): \(Self.truncateForUI(apiMessage))"
            }
            return "Erro do provedor (HTTP \(statusCode))."
        }
    }

    enum HTTPFailureKind: String {
        case billingOrQuota
        case unauthorized
        case rateLimited
        case modelUnavailable
        case serverError
        case other
    }

    static func classifyHTTPFailure(statusCode: Int, body: String) -> HTTPFailureKind {
        let lower = body.lowercased()
        if statusCode == 402
            || lower.contains("insufficient balance")
            || lower.contains("insufficient_quota")
            || lower.contains("insufficient credits")
            || lower.contains("payment required")
            || lower.contains("billing_hard_limit")
            || lower.contains("credit balance")
            || (lower.contains("quota")
                && (lower.contains("exceed")
                    || lower.contains("exhaust")
                    || lower.contains("insufficient")))
        {
            return .billingOrQuota
        }
        if statusCode == 401
            || statusCode == 403
            || lower.contains("invalid api key")
            || lower.contains("incorrect api key")
            || lower.contains("invalid_api_key")
            || lower.contains("authentication")
            || lower.contains("unauthorized")
            || lower.contains("permission denied")
        {
            return .unauthorized
        }
        if statusCode == 429
            || lower.contains("rate limit")
            || lower.contains("rate_limit")
            || lower.contains("too many requests")
        {
            return .rateLimited
        }
        if lower.contains("no longer available")
            || lower.contains("model_not_found")
            || lower.contains("is not found")
            || (statusCode == 404
                && (lower.contains("model")
                    || lower.contains("not_found")
                    || lower.contains("not found")))
        {
            return .modelUnavailable
        }
        if (500...599).contains(statusCode) {
            return .serverError
        }
        return .other
    }

    static func truncateForUI(_ text: String, limit: Int = 140) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Pulls `error.message` / `message` from OpenAI-style and similar JSON bodies.
    static func extractAPIErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = json["message"] as? String {
            return message
        }
        return nil
    }
}

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case apple
    case deepl
    case google
    case groq
    case gemini
    case mistral
    case deepSeek
    case openRouter
    case openAICompatible
    case customHTTP

    var id: String { rawValue }

    /// Nome limpo do motor (sem sufixos entre parênteses).
    var displayName: String {
        switch self {
        case .apple: return "Apple Translation"
        case .deepl: return "DeepL"
        case .google: return "Google Translate"
        case .groq: return "Groq"
        case .gemini: return "Gemini"
        case .mistral: return "Mistral"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        case .openAICompatible: return "LM Studio / OpenAI"
        case .customHTTP: return "HTTP personalizado"
        }
    }

    /// SF Symbol que identifica o motor na UI.
    var symbolName: String {
        switch self {
        case .apple: return "apple.logo"
        case .deepl: return "character.book.closed"
        case .google: return "globe"
        case .groq: return "bolt.fill"
        case .gemini: return "sparkles"
        case .mistral: return "wind"
        case .deepSeek: return "brain.head.profile"
        case .openRouter: return "arrow.triangle.branch"
        case .openAICompatible: return "desktopcomputer"
        case .customHTTP: return "curlybraces"
        }
    }

    /// Agrupamento no seletor de motores (alternativa aos parênteses no nome).
    var pickerGroup: EnginePickerGroup {
        switch self {
        case .apple: return .onDevice
        case .deepl, .google: return .classic
        case .groq, .gemini, .mistral, .deepSeek, .openRouter: return .cloudAI
        case .openAICompatible, .customHTTP: return .advanced
        }
    }

    /// Etiquetas curtas exibidas como chips (ex.: IA, Grátis) — sem “(...)” no nome.
    var badges: [EngineBadge] {
        switch self {
        case .apple: return [.local, .default]
        case .deepl: return [.classic, .freeTier]
        case .google: return [.classic]
        case .groq, .gemini, .mistral, .openRouter: return [.ai, .freeTier]
        case .deepSeek: return [.ai, .paid]
        case .openAICompatible: return [.ai, .local]
        case .customHTTP: return [.advanced]
        }
    }

    /// On-device or local-first defaults (no cloud account required).
    var isLocalDefault: Bool {
        self == .apple || self == .openAICompatible
    }

    /// Cloud LLM that translates via chat/completions-style prompting.
    var isAIEngine: Bool {
        switch self {
        case .groq, .gemini, .mistral, .deepSeek, .openRouter, .openAICompatible:
            return true
        default:
            return false
        }
    }

    /// AI engines whose preferred model can be refreshed from the provider API.
    var supportsLiveModelCatalog: Bool {
        switch self {
        case .groq, .gemini, .mistral, .deepSeek, .openRouter:
            return true
        default:
            return false
        }
    }

    /// Help text shown under the provider picker for free AI engines.
    var setupHint: String? {
        switch self {
        case .groq:
            return "Chave grátis em console.groq.com — API OpenAI-compatible."
        case .gemini:
            return "Chave grátis em aistudio.google.com — Google AI Studio."
        case .mistral:
            return "Chave grátis em console.mistral.ai — La Plateforme."
        case .deepSeek:
            return "Chave em platform.deepseek.com — requer saldo/créditos na conta."
        case .openRouter:
            return "Chave grátis em openrouter.ai — use modelos com sufixo :free ou openrouter/free."
        case .apple:
            return "Tradução on-device da Apple — sem API key."
        case .openAICompatible:
            return "Servidor local OpenAI-compatible (LM Studio, Ollama, etc.)."
        default:
            return nil
        }
    }

    /// Default model id when the user has not customized it.
    var defaultModel: String? {
        switch self {
        case .groq: return "llama-3.1-8b-instant"
        case .gemini: return "gemini-flash-lite-latest"
        case .mistral: return "mistral-small-latest"
        case .deepSeek: return "deepseek-chat"
        case .openRouter: return "openrouter/free"
        case .openAICompatible: return "local-model"
        default: return nil
        }
    }

    /// Preferência ordenada de modelos para tradução (rápido / estável). O catálogo escolhe o 1º disponível.
    var preferredModelsForTranslation: [String] {
        switch self {
        case .groq:
            return [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "meta-llama/llama-4-scout-17b-16e-instruct",
                "openai/gpt-oss-20b"
            ]
        case .gemini:
            return [
                "gemini-flash-lite-latest",
                "gemini-3.5-flash-lite",
                "gemini-3.1-flash-lite",
                "gemini-2.5-flash-lite",
                "gemini-flash-latest",
                "gemini-3.6-flash",
                "gemini-3.5-flash",
                "gemini-2.5-flash"
            ]
        case .mistral:
            return [
                "mistral-small-latest",
                "mistral-small",
                "open-mistral-nemo",
                "mistral-medium-latest"
            ]
        case .deepSeek:
            return [
                "deepseek-chat",
                "deepseek-v4-flash",
                "deepseek-reasoner",
                "deepseek-v4-pro"
            ]
        case .openRouter:
            return [
                "openrouter/free",
                "meta-llama/llama-3.3-70b-instruct:free",
                "google/gemma-3-27b-it:free"
            ]
        default:
            return defaultModel.map { [$0] } ?? []
        }
    }

    /// Fixed OpenAI-compatible base URL for preset AI providers.
    var openAICompatibleBaseURL: String? {
        switch self {
        case .groq: return "https://api.groq.com/openai/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .deepSeek: return "https://api.deepseek.com"
        case .openRouter: return "https://openrouter.ai/api/v1"
        default: return nil
        }
    }

    var apiKeychainKey: KeychainStore.Key? {
        switch self {
        case .deepl: return .deeplAPIKey
        case .google: return .googleAPIKey
        case .groq: return .groqAPIKey
        case .gemini: return .geminiAPIKey
        case .mistral: return .mistralAPIKey
        case .deepSeek: return .deepSeekAPIKey
        case .openRouter: return .openRouterAPIKey
        case .openAICompatible: return .openAIAPIKey
        default: return nil
        }
    }
}

/// Agrupamento visual no picker de motores.
enum EnginePickerGroup: String, CaseIterable, Identifiable {
    case onDevice
    case classic
    case cloudAI
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: return "No dispositivo"
        case .classic: return "Tradução clássica"
        case .cloudAI: return "IA na nuvem"
        case .advanced: return "Avançado"
        }
    }

    var providers: [ProviderKind] {
        ProviderKind.allCases.filter { $0.pickerGroup == self }
    }
}

/// Chip curto ao lado do nome do motor (substitui “(IA gratuita)” etc.).
enum EngineBadge: String, Hashable {
    case ai = "IA"
    case local = "Local"
    case classic = "Tradução"
    case freeTier = "Grátis"
    case paid = "Pago"
    case `default` = "Padrão"
    case advanced = "Avançado"
}
