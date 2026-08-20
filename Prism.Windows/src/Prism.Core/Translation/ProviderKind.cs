namespace Prism.Core.Translation;

/// <summary>
/// Windows providers — Apple Translation is intentionally omitted.
/// Azure is the Microsoft-native default cloud engine.
/// </summary>
public enum ProviderKind
{
    Azure,
    DeepL,
    Google,
    OpenAICompatible,
    CustomHttp,
}

public static class ProviderKindExtensions
{
    public static string ToStorageKey(this ProviderKind kind) => kind switch
    {
        ProviderKind.Azure => "azure",
        ProviderKind.DeepL => "deepl",
        ProviderKind.Google => "google",
        ProviderKind.OpenAICompatible => "openAICompatible",
        ProviderKind.CustomHttp => "customHTTP",
        _ => kind.ToString().ToLowerInvariant(),
    };

    public static ProviderKind Parse(string? raw) => raw switch
    {
        "azure" => ProviderKind.Azure,
        "deepl" => ProviderKind.DeepL,
        "google" => ProviderKind.Google,
        "openAICompatible" => ProviderKind.OpenAICompatible,
        "customHTTP" => ProviderKind.CustomHttp,
        "apple" => ProviderKind.Azure, // migrate macOS installs toward Azure
        _ => ProviderKind.Azure,
    };

    public static string DisplayName(this ProviderKind kind) => kind switch
    {
        ProviderKind.Azure => "Azure Translator",
        ProviderKind.DeepL => "DeepL",
        ProviderKind.Google => "Google Translate",
        ProviderKind.OpenAICompatible => "LM Studio / OpenAI",
        ProviderKind.CustomHttp => "Custom HTTP",
        _ => kind.ToString(),
    };

    public static string? SetupHint(this ProviderKind kind) => kind switch
    {
        ProviderKind.Azure => "Microsoft Azure AI Translator — set the API key in Settings.",
        ProviderKind.OpenAICompatible => "Local OpenAI-compatible server (LM Studio, Ollama, etc.).",
        _ => null,
    };

    public static string? DefaultModel(this ProviderKind kind) => kind switch
    {
        ProviderKind.OpenAICompatible => "local-model",
        _ => null,
    };
}
