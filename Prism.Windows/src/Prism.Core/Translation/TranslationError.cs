using System.Text.Json;

namespace Prism.Core.Translation;

public sealed class TranslationError : Exception
{
    public enum Kind
    {
        ProviderUnavailable,
        InvalidConfiguration,
        EmptyResponse,
        HttpStatus,
        UnsupportedLanguagePair,
    }

    public enum HttpFailureKind
    {
        BillingOrQuota,
        Unauthorized,
        RateLimited,
        ModelUnavailable,
        ServerError,
        Other,
    }

    public Kind ErrorKind { get; }
    public int? StatusCode { get; }
    public string? ResponseBody { get; }

    private TranslationError(Kind kind, string message, int? statusCode = null, string? body = null)
        : base(message)
    {
        ErrorKind = kind;
        StatusCode = statusCode;
        ResponseBody = body;
    }

    public bool IsUnsupportedLanguagePair =>
        ErrorKind == Kind.UnsupportedLanguagePair
        || (Message.Contains("not supported", StringComparison.OrdinalIgnoreCase)
            || Message.Contains("não suportado", StringComparison.OrdinalIgnoreCase));

    public static TranslationError ProviderUnavailable(string name) =>
        new(Kind.ProviderUnavailable, $"Provider unavailable: {name}");

    public static TranslationError InvalidConfiguration(string message) =>
        new(Kind.InvalidConfiguration, message);

    public static TranslationError EmptyResponse() =>
        new(Kind.EmptyResponse, "Empty response from provider");

    public static TranslationError HttpStatus(int statusCode, string body) =>
        new(Kind.HttpStatus, UserFacingHttpMessage(statusCode, body), statusCode, body);

    public static TranslationError UnsupportedLanguagePair(string message) =>
        new(Kind.UnsupportedLanguagePair, message);

    public static string UserFacingHttpMessage(int statusCode, string body)
    {
        return ClassifyHttpFailure(statusCode, body) switch
        {
            HttpFailureKind.BillingOrQuota =>
                "API balance or quota exhausted. Top up credits with the provider or switch engines in Settings.",
            HttpFailureKind.Unauthorized =>
                "Invalid API key or missing permission. Check the key in Settings.",
            HttpFailureKind.RateLimited =>
                "Request limit reached. Wait a moment and try again.",
            HttpFailureKind.ModelUnavailable =>
                "API model unavailable or discontinued. Update the model in Settings.",
            HttpFailureKind.ServerError =>
                $"The provider is unavailable (HTTP {statusCode}). Try again in a moment.",
            _ when ExtractApiErrorMessage(body) is { Length: > 0 } apiMessage =>
                $"Provider error (HTTP {statusCode}): {TruncateForUi(apiMessage)}",
            _ => $"Provider error (HTTP {statusCode}).",
        };
    }

    public static HttpFailureKind ClassifyHttpFailure(int statusCode, string body)
    {
        var lower = body.ToLowerInvariant();
        if (statusCode == 402
            || lower.Contains("insufficient balance")
            || lower.Contains("insufficient_quota")
            || lower.Contains("insufficient credits")
            || lower.Contains("payment required")
            || lower.Contains("billing_hard_limit")
            || lower.Contains("credit balance")
            || (lower.Contains("quota")
                && (lower.Contains("exceed")
                    || lower.Contains("exhaust")
                    || lower.Contains("insufficient"))))
        {
            return HttpFailureKind.BillingOrQuota;
        }

        if (statusCode is 401 or 403
            || lower.Contains("invalid api key")
            || lower.Contains("incorrect api key")
            || lower.Contains("invalid_api_key")
            || lower.Contains("api key not valid")
            || lower.Contains("api key is not valid")
            || lower.Contains("pass a valid api key")
            || lower.Contains("authentication")
            || lower.Contains("unauthorized")
            || lower.Contains("permission denied"))
        {
            return HttpFailureKind.Unauthorized;
        }

        if (statusCode == 429
            || lower.Contains("rate limit")
            || lower.Contains("rate_limit")
            || lower.Contains("too many requests"))
        {
            return HttpFailureKind.RateLimited;
        }

        if (lower.Contains("no longer available")
            || lower.Contains("model_not_found")
            || lower.Contains("is not found")
            || (statusCode == 404
                && (lower.Contains("model")
                    || lower.Contains("not_found")
                    || lower.Contains("not found"))))
        {
            return HttpFailureKind.ModelUnavailable;
        }

        if (statusCode is >= 500 and <= 599)
            return HttpFailureKind.ServerError;

        return HttpFailureKind.Other;
    }

    public static string TruncateForUi(string text, int limit = 140)
    {
        if (text.Length <= limit) return text;
        return text[..limit].Trim() + "…";
    }

    public static string? ExtractApiErrorMessage(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.Object
                && error.TryGetProperty("message", out var nested)
                && nested.ValueKind == JsonValueKind.String)
            {
                return nested.GetString();
            }

            if (doc.RootElement.TryGetProperty("message", out var message)
                && message.ValueKind == JsonValueKind.String)
            {
                return message.GetString();
            }
        }
        catch (JsonException)
        {
            // ignore non-JSON bodies
        }

        return null;
    }
}
