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
            return "Erro HTTP \(code): \(body)"
        case .appleTranslationFailed(let message):
            return "Apple Translation: \(message)"
        }
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

    var displayName: String {
        switch self {
        case .apple: return "Apple Translation (padrão)"
        case .deepl: return "DeepL"
        case .google: return "Google Cloud Translation"
        case .groq: return "Groq (IA gratuita)"
        case .gemini: return "Google Gemini (IA gratuita)"
        case .mistral: return "Mistral (IA gratuita)"
        case .deepSeek: return "DeepSeek (IA)"
        case .openRouter: return "OpenRouter (IA gratuita)"
        case .openAICompatible: return "OpenAI-compatible / LM Studio"
        case .customHTTP: return "Custom HTTP"
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
            return "Chave em platform.deepseek.com — API OpenAI-compatible (créditos iniciais)."
        case .openRouter:
            return "Chave grátis em openrouter.ai — use modelos com sufixo :free ou openrouter/free."
        default:
            return nil
        }
    }

    /// Default model id when the user has not customized it.
    var defaultModel: String? {
        switch self {
        case .groq: return "llama-3.1-8b-instant"
        case .gemini: return "gemini-2.5-flash"
        case .mistral: return "mistral-small-latest"
        case .deepSeek: return "deepseek-v4-flash"
        case .openRouter: return "openrouter/free"
        case .openAICompatible: return "local-model"
        default: return nil
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
}
