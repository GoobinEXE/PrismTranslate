import Foundation

protocol TranslationProvider {
    var id: String { get }
    var displayName: String { get }
    func translate(_ text: String, from: String?, to: String) async throws -> String
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
    case openAICompatible
    case customHTTP

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple Translation (padrão)"
        case .deepl: return "DeepL"
        case .google: return "Google Cloud Translation"
        case .openAICompatible: return "OpenAI-compatible / LM Studio"
        case .customHTTP: return "Custom HTTP"
        }
    }

    var isLocalDefault: Bool {
        self == .apple || self == .openAICompatible
    }
}
