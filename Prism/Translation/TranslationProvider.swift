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
            return String(format: String(localized: "Provider unavailable: %@"), name)
        case .invalidConfiguration(let message):
            return message
        case .emptyResponse:
            return String(localized: "Empty response from provider")
        case .httpStatus(let code, let body):
            return Self.userFacingHTTPMessage(statusCode: code, body: body)
        case .appleTranslationFailed(let message):
            return String(format: String(localized: "Apple Translation: %@"), message)
        }
    }

    /// True when Apple Translation rejected the pair (often source == target).
    var isUnsupportedLanguagePair: Bool {
        guard case .appleTranslationFailed(let message) = self else { return false }
        let lower = message.lowercased()
        return lower.contains("not supported") || lower.contains("não suportado")
    }

    /// Safe technical summary for logs — never includes HTTP response bodies.
    var debugLogSummary: String {
        switch self {
        case .providerUnavailable(let name):
            return "providerUnavailable(\(name))"
        case .invalidConfiguration(let message):
            return "invalidConfiguration(\(message))"
        case .emptyResponse:
            return "emptyResponse"
        case .httpStatus(let code, let body):
            let kind = Self.classifyHTTPFailure(statusCode: code, body: body)
            return "httpStatus(\(code), \(kind.logLabel))"
        case .appleTranslationFailed(let message):
            return "appleTranslationFailed(\(message))"
        }
    }

    /// Maps provider HTTP failures to short user-facing copy.
    static func userFacingHTTPMessage(statusCode: Int, body: String) -> String {
        switch classifyHTTPFailure(statusCode: statusCode, body: body) {
        case .billingOrQuota:
            return String(localized: "API balance or quota exhausted. Top up credits with the provider or switch engines in Settings.")
        case .unauthorized:
            return String(localized: "Invalid API key or missing permission. Check the key in Settings.")
        case .rateLimited:
            return String(localized: "Request limit reached. Wait a moment and try again.")
        case .modelUnavailable:
            return String(localized: "API model unavailable or discontinued. Update the model in Settings.")
        case .serverError:
            return String(format: String(localized: "The provider is unavailable (HTTP %lld). Try again in a moment."), Int64(statusCode))
        case .other:
            if let apiMessage = extractAPIErrorMessage(from: body), !apiMessage.isEmpty {
                return String(
                    format: String(localized: "Provider error (HTTP %lld): %@"),
                    Int64(statusCode),
                    Self.truncateForUI(apiMessage)
                )
            }
            return String(format: String(localized: "Provider error (HTTP %lld)."), Int64(statusCode))
        }
    }

    enum HTTPFailureKind: String {
        case billingOrQuota
        case unauthorized
        case rateLimited
        case modelUnavailable
        case serverError
        case other

        var logLabel: String {
            switch self {
            case .billingOrQuota: return "saldo ou cota esgotados"
            case .unauthorized: return "chave inválida ou sem permissão"
            case .rateLimited: return "limite de requisições"
            case .modelUnavailable: return "modelo indisponível ou descontinuado"
            case .serverError: return "erro no servidor do provedor"
            case .other: return "erro do provedor"
            }
        }
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
            || lower.contains("api key not valid")
            || lower.contains("api key is not valid")
            || lower.contains("pass a valid api key")
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

extension Error {
    /// Log-safe error description — strips HTTP bodies from `TranslationError`.
    var debugLogSummary: String {
        if let translation = self as? TranslationError {
            return translation.debugLogSummary
        }
        return localizedDescription
    }
}

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case apple
    case deepl
    case google
    case openAICompatible
    case customHTTP

    var id: String { rawValue }

    /// Nome limpo do motor (sem sufixos entre parênteses).
    var displayName: String {
        switch self {
        case .apple: return "Apple Translation"
        case .deepl: return "DeepL"
        case .google: return "Google Translate"
        case .openAICompatible: return "LM Studio / OpenAI"
        case .customHTTP: return String(localized: "Custom HTTP")
        }
    }

    /// SF Symbol que identifica o motor na UI.
    var symbolName: String {
        switch self {
        case .apple: return "apple.logo"
        case .deepl: return "character.book.closed"
        case .google: return "globe"
        case .openAICompatible: return "desktopcomputer"
        case .customHTTP: return "curlybraces"
        }
    }

    /// Agrupamento no seletor de motores (alternativa aos parênteses no nome).
    var pickerGroup: EnginePickerGroup {
        switch self {
        case .apple: return .onDevice
        case .deepl, .google: return .classic
        case .openAICompatible, .customHTTP: return .advanced
        }
    }

    /// Etiquetas curtas exibidas como chips (ex.: IA, Grátis) — sem “(...)” no nome.
    var badges: [EngineBadge] {
        switch self {
        case .apple: return [.local, .default]
        case .deepl: return [.classic, .freeTier]
        case .google: return [.classic]
        case .openAICompatible: return [.ai, .local]
        case .customHTTP: return [.advanced]
        }
    }

    /// Help text shown under the provider picker.
    var setupHint: String? {
        switch self {
        case .apple:
            return String(localized: "Apple on-device translation — no API key.")
        case .openAICompatible:
            return String(localized: "Local OpenAI-compatible server (LM Studio, Ollama, etc.).")
        default:
            return nil
        }
    }

    /// Default model id when the user has not customized it.
    var defaultModel: String? {
        switch self {
        case .openAICompatible: return "local-model"
        default: return nil
        }
    }

    var apiKeychainKey: KeychainStore.Key? {
        switch self {
        case .deepl: return .deeplAPIKey
        case .google: return .googleAPIKey
        case .openAICompatible: return .openAIAPIKey
        default: return nil
        }
    }
}

/// Agrupamento visual no picker de motores.
enum EnginePickerGroup: String, CaseIterable, Identifiable {
    case onDevice
    case classic
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: return String(localized: "On this device")
        case .classic: return String(localized: "Classic translation")
        case .advanced: return String(localized: "Advanced")
        }
    }

    var providers: [ProviderKind] {
        ProviderKind.allCases.filter { $0.pickerGroup == self }
    }
}

/// Chip curto ao lado do nome do motor (substitui “(IA gratuita)” etc.).
enum EngineBadge: String, Hashable {
    case ai
    case local
    case classic
    case freeTier
    case paid
    case `default`
    case advanced

    var title: String {
        switch self {
        case .ai: String(localized: "AI")
        case .local: String(localized: "Local")
        case .classic: String(localized: "Translation")
        case .freeTier: String(localized: "Free")
        case .paid: String(localized: "Paid")
        case .default: String(localized: "Default")
        case .advanced: String(localized: "Advanced")
        }
    }
}
