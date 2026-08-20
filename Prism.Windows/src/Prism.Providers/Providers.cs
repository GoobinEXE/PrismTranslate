using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Prism.Core.Translation;

namespace Prism.Providers;

internal static class HttpForm
{
    public static string Encode(string value)
    {
        var encoded = Uri.EscapeDataString(value);
        return encoded.Replace("%20", "+");
    }
}

public sealed class DeepLProvider : ITranslationProvider
{
    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly bool _useFreeApi;

    public string Id => ProviderKind.DeepL.ToStorageKey();
    public string DisplayName => ProviderKind.DeepL.DisplayName();

    public DeepLProvider(string apiKey, bool useFreeApi = true, HttpClient? http = null)
    {
        _apiKey = apiKey;
        _useFreeApi = useFreeApi;
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(12) };
    }

    public async Task<TranslationOutcome> TranslateAsync(
        string text,
        string? from,
        string to,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_apiKey))
            throw TranslationError.InvalidConfiguration("Set the DeepL API key in Settings");

        var host = _useFreeApi ? "api-free.deepl.com" : "api.deepl.com";
        var url = $"https://{host}/v2/translate";

        var body = new StringBuilder();
        body.Append("text=").Append(HttpForm.Encode(text));
        body.Append("&target_lang=").Append(HttpForm.Encode(ApiCode(to, isTarget: true)));
        if (!string.IsNullOrEmpty(from))
            body.Append("&source_lang=").Append(HttpForm.Encode(ApiCode(from, isTarget: false)));

        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Content = new StringContent(body.ToString(), Encoding.UTF8, "application/x-www-form-urlencoded");
        request.Headers.Authorization = new AuthenticationHeaderValue("DeepL-Auth-Key", _apiKey);

        using var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var raw = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
            throw TranslationError.HttpStatus((int)response.StatusCode, raw);

        using var doc = JsonDocument.Parse(raw);
        var translations = doc.RootElement.GetProperty("translations");
        if (translations.GetArrayLength() == 0)
            throw TranslationError.EmptyResponse();

        var first = translations[0];
        var translated = first.GetProperty("text").GetString() ?? throw TranslationError.EmptyResponse();
        string? detected = null;
        if (first.TryGetProperty("detected_source_language", out var det)
            && det.ValueKind == JsonValueKind.String
            && det.GetString() is { Length: > 0 } detCode)
        {
            detected = LanguageCode.Normalize(detCode);
        }

        return new TranslationOutcome(translated, detected);
    }

    public static string ApiCode(string code, bool isTarget) => code.ToLowerInvariant() switch
    {
        "en" => "EN",
        "pt" or "pt-br" => isTarget ? "PT-BR" : "PT",
        "pt-pt" => isTarget ? "PT-PT" : "PT",
        "zh" or "zh-cn" or "zh-hans" => isTarget ? "ZH-HANS" : "ZH",
        "zh-hant" or "zh-tw" => isTarget ? "ZH-HANT" : "ZH",
        _ => code.ToUpperInvariant(),
    };
}

public sealed class GoogleTranslateProvider : ITranslationProvider
{
    private readonly HttpClient _http;
    private readonly string _apiKey;

    public string Id => ProviderKind.Google.ToStorageKey();
    public string DisplayName => ProviderKind.Google.DisplayName();

    public GoogleTranslateProvider(string apiKey, HttpClient? http = null)
    {
        _apiKey = apiKey;
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(12) };
    }

    public async Task<TranslationOutcome> TranslateAsync(
        string text,
        string? from,
        string to,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_apiKey))
            throw TranslationError.InvalidConfiguration("Set the Google API key in Settings");

        var body = new StringBuilder();
        body.Append("q=").Append(HttpForm.Encode(text));
        body.Append("&target=").Append(HttpForm.Encode(ApiCode(to)));
        body.Append("&format=text");
        if (!string.IsNullOrEmpty(from))
            body.Append("&source=").Append(HttpForm.Encode(ApiCode(from)));

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            "https://translation.googleapis.com/language/translate/v2");
        request.Content = new StringContent(body.ToString(), Encoding.UTF8, "application/x-www-form-urlencoded");
        request.Headers.TryAddWithoutValidation("X-Goog-Api-Key", _apiKey);

        using var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var raw = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
            throw TranslationError.HttpStatus((int)response.StatusCode, raw);

        using var doc = JsonDocument.Parse(raw);
        var translations = doc.RootElement.GetProperty("data").GetProperty("translations");
        if (translations.GetArrayLength() == 0)
            throw TranslationError.EmptyResponse();

        var first = translations[0];
        var translated = first.GetProperty("translatedText").GetString()
            ?? throw TranslationError.EmptyResponse();
        string? detected = null;
        if (first.TryGetProperty("detectedSourceLanguage", out var det)
            && det.ValueKind == JsonValueKind.String
            && det.GetString() is { Length: > 0 } detCode)
        {
            detected = LanguageCode.Normalize(detCode);
        }

        return new TranslationOutcome(translated, detected);
    }

    public static string ApiCode(string code) => code switch
    {
        "zh-Hans" => "zh-CN",
        "zh-Hant" => "zh-TW",
        _ => code,
    };
}

public sealed class OpenAICompatibleProvider : ITranslationProvider
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _model;
    private readonly string _apiKey;
    private readonly bool _requiresApiKey;

    public string Id => ProviderKind.OpenAICompatible.ToStorageKey();
    public string DisplayName => ProviderKind.OpenAICompatible.DisplayName();

    public OpenAICompatibleProvider(
        string baseUrl,
        string model,
        string apiKey = "",
        bool requiresApiKey = false,
        HttpClient? http = null)
    {
        _baseUrl = baseUrl;
        _model = model;
        _apiKey = apiKey;
        _requiresApiKey = requiresApiKey;
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    }

    public async Task<TranslationOutcome> TranslateAsync(
        string text,
        string? from,
        string to,
        CancellationToken cancellationToken = default)
    {
        var trimmedBase = _baseUrl.Trim().TrimEnd('/');
        var trimmedModel = _model.Trim();
        if (string.IsNullOrEmpty(trimmedBase) || string.IsNullOrEmpty(trimmedModel))
            throw TranslationError.InvalidConfiguration($"Set base URL and model for {DisplayName}");
        if (_requiresApiKey && string.IsNullOrWhiteSpace(_apiKey))
            throw TranslationError.InvalidConfiguration($"Set the API key for {DisplayName} in Settings");

        if (!Uri.TryCreate($"{trimmedBase}/chat/completions", UriKind.Absolute, out var url))
            throw TranslationError.InvalidConfiguration("Invalid base URL");

        var prompt = AITranslationPrompt.Make(text, from, to);
        var payload = new
        {
            model = trimmedModel,
            temperature = 0,
            messages = new object[]
            {
                new { role = "system", content = prompt.System },
                new { role = "user", content = prompt.User },
            },
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Content = new StringContent(
            JsonSerializer.Serialize(payload),
            Encoding.UTF8,
            "application/json");
        if (!string.IsNullOrWhiteSpace(_apiKey))
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        using var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var raw = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
            throw TranslationError.HttpStatus((int)response.StatusCode, Encoding.UTF8.GetString(raw));

        var content = ParseChatContent(raw);
        return new TranslationOutcome(content);
    }

    public static string ParseChatContent(byte[] data)
    {
        using var doc = JsonDocument.Parse(data);
        if (!doc.RootElement.TryGetProperty("choices", out var choices)
            || choices.GetArrayLength() == 0)
        {
            throw TranslationError.EmptyResponse();
        }

        var message = choices[0].GetProperty("message");
        if (!message.TryGetProperty("content", out var contentEl)
            || contentEl.ValueKind != JsonValueKind.String)
        {
            throw TranslationError.EmptyResponse();
        }

        var content = contentEl.GetString()?.Trim();
        if (string.IsNullOrEmpty(content))
            throw TranslationError.EmptyResponse();
        return content;
    }
}

public sealed class CustomHttpProvider : ITranslationProvider
{
    private readonly HttpClient _http;
    private readonly string _url;
    private readonly string _method;
    private readonly string _headersJson;
    private readonly string _bodyTemplate;
    private readonly string _responseJsonPath;

    public string Id => ProviderKind.CustomHttp.ToStorageKey();
    public string DisplayName => ProviderKind.CustomHttp.DisplayName();

    public CustomHttpProvider(
        string url,
        string method,
        string headersJson,
        string bodyTemplate,
        string responseJsonPath,
        HttpClient? http = null)
    {
        _url = url;
        _method = method;
        _headersJson = headersJson;
        _bodyTemplate = bodyTemplate;
        _responseJsonPath = responseJsonPath;
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
    }

    public async Task<TranslationOutcome> TranslateAsync(
        string text,
        string? from,
        string to,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_url) || !Uri.TryCreate(_url, UriKind.Absolute, out var endpoint))
            throw TranslationError.InvalidConfiguration("Set the Custom HTTP URL");

        using var request = new HttpRequestMessage(new HttpMethod(_method.ToUpperInvariant()), endpoint);

        try
        {
            using var headersDoc = JsonDocument.Parse(_headersJson);
            foreach (var prop in headersDoc.RootElement.EnumerateObject())
            {
                if (prop.Value.ValueKind == JsonValueKind.String)
                    request.Headers.TryAddWithoutValidation(prop.Name, prop.Value.GetString());
            }
        }
        catch (JsonException)
        {
            // ignore invalid headers JSON
        }

        var body = _bodyTemplate
            .Replace("{{text}}", JsonEscape(text), StringComparison.Ordinal)
            .Replace("{{to}}", JsonEscape(to), StringComparison.Ordinal)
            .Replace("{{from}}", JsonEscape(from ?? ""), StringComparison.Ordinal);

        if (!string.Equals(_method, "GET", StringComparison.OrdinalIgnoreCase))
        {
            request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        }

        using var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var rawBytes = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        var raw = Encoding.UTF8.GetString(rawBytes);
        if (!response.IsSuccessStatusCode)
            throw TranslationError.HttpStatus((int)response.StatusCode, raw);

        if (string.IsNullOrEmpty(_responseJsonPath))
        {
            if (string.IsNullOrEmpty(raw))
                throw TranslationError.EmptyResponse();
            return new TranslationOutcome(raw);
        }

        using var doc = JsonDocument.Parse(rawBytes);
        var extracted = Extract(_responseJsonPath, doc.RootElement)
            ?? throw TranslationError.EmptyResponse();
        return new TranslationOutcome(extracted);
    }

    public static string JsonEscape(string value)
    {
        var result = value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\t", "\\t", StringComparison.Ordinal)
            .Replace("\0", "", StringComparison.Ordinal);
        return new string(result.Where(c => !char.IsControl(c) || c is '\n' or '\r' or '\t').ToArray());
    }

    public static bool HeadersContainCredentials(string headersJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(headersJson);
            var sensitive = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "authorization", "x-api-key", "x-goog-api-key", "api-key",
            };
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                if (sensitive.Contains(prop.Name))
                    return true;
                if (prop.Value.ValueKind == JsonValueKind.String
                    && prop.Value.GetString()?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true)
                {
                    return true;
                }
            }
        }
        catch (JsonException)
        {
            return false;
        }

        return false;
    }

    public static string? Extract(string path, JsonElement root)
    {
        var parts = path.Split('.', StringSplitOptions.RemoveEmptyEntries);
        var current = root;
        foreach (var part in parts)
        {
            // Match Swift: array index only when current is an array; otherwise treat as object key
            // (so path "0" resolves {"0":"zero"} as a dictionary key).
            if (int.TryParse(part, out var index) && current.ValueKind == JsonValueKind.Array)
            {
                if (index < 0 || index >= current.GetArrayLength())
                    return null;
                current = current[index];
            }
            else if (current.ValueKind == JsonValueKind.Object && current.TryGetProperty(part, out var next))
            {
                current = next;
            }
            else
            {
                return null;
            }
        }

        return current.ValueKind switch
        {
            JsonValueKind.String => current.GetString(),
            JsonValueKind.Number => current.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => null,
        };
    }
}

public sealed class AzureTranslatorProvider : ITranslationProvider
{
    private readonly string _apiKey;
    private readonly string _region;
    private readonly HttpClient _http;

    public string Id => ProviderKind.Azure.ToStorageKey();
    public string DisplayName => ProviderKind.Azure.DisplayName();

    public AzureTranslatorProvider(string apiKey, string region = "global", HttpClient? http = null)
    {
        _apiKey = apiKey;
        _region = string.IsNullOrWhiteSpace(region) ? "global" : region;
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
    }

    public async Task<TranslationOutcome> TranslateAsync(
        string text,
        string? from,
        string to,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_apiKey))
            throw TranslationError.InvalidConfiguration("Set the Azure Translator API key in Settings");

        var target = AzureCode(to);
        var query = $"api-version=3.0&to={Uri.EscapeDataString(target)}";
        if (!string.IsNullOrEmpty(from))
            query += $"&from={Uri.EscapeDataString(AzureCode(from))}";

        var url = $"https://api.cognitive.microsofttranslator.com/translate?{query}";
        var payload = JsonSerializer.Serialize(new[] { new { Text = text } });

        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Content = new StringContent(payload, Encoding.UTF8, "application/json");
        request.Headers.TryAddWithoutValidation("Ocp-Apim-Subscription-Key", _apiKey);
        if (!string.Equals(_region, "global", StringComparison.OrdinalIgnoreCase))
            request.Headers.TryAddWithoutValidation("Ocp-Apim-Subscription-Region", _region);

        using var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var raw = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
            throw TranslationError.HttpStatus((int)response.StatusCode, raw);

        using var doc = JsonDocument.Parse(raw);
        if (doc.RootElement.GetArrayLength() == 0)
            throw TranslationError.EmptyResponse();

        var first = doc.RootElement[0];
        var translations = first.GetProperty("translations");
        if (translations.GetArrayLength() == 0)
            throw TranslationError.EmptyResponse();

        var translated = translations[0].GetProperty("text").GetString()
            ?? throw TranslationError.EmptyResponse();

        string? detected = null;
        if (first.TryGetProperty("detectedLanguage", out var det)
            && det.TryGetProperty("language", out var lang)
            && lang.ValueKind == JsonValueKind.String
            && lang.GetString() is { Length: > 0 } code)
        {
            detected = LanguageCode.Normalize(code);
        }

        return new TranslationOutcome(translated, detected);
    }

    public static string AzureCode(string code) => code switch
    {
        "zh-Hans" => "zh-Hans",
        "zh-Hant" => "zh-Hant",
        _ => LanguageCode.Normalize(code),
    };
}

public static class ProviderFactory
{
    public static ITranslationProvider Create(
        Prism.Core.Settings.AppSettings settings,
        Func<string, string?> loadSecret)
    {
        return settings.ProviderKind switch
        {
            ProviderKind.Azure => new AzureTranslatorProvider(
                loadSecret("azure") ?? "",
                settings.AzureRegion),
            ProviderKind.DeepL => new DeepLProvider(
                loadSecret("deepl") ?? "",
                settings.DeepLUseFreeApi),
            ProviderKind.Google => new GoogleTranslateProvider(loadSecret("google") ?? ""),
            ProviderKind.OpenAICompatible => new OpenAICompatibleProvider(
                settings.OpenAIBaseUrl,
                settings.OpenAIModel,
                loadSecret("openai") ?? ""),
            ProviderKind.CustomHttp => new CustomHttpProvider(
                settings.CustomHttpUrl,
                settings.CustomHttpMethod,
                settings.CustomHttpHeadersJson,
                settings.CustomHttpBodyTemplate,
                settings.CustomHttpResponsePath),
            _ => throw TranslationError.ProviderUnavailable(settings.ProviderKind.DisplayName()),
        };
    }
}
