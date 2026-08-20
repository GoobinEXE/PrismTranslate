using System.Text.Json;
using System.Text.Json.Serialization;
using Prism.Core.Hotkeys;
using Prism.Core.Translation;

namespace Prism.Core.Settings;

public sealed class AppSettings
{
    public bool IsEnabled { get; set; } = true;
    public bool EnterTranslatesAndSends { get; set; }

    public string? IncomingSourceLanguage { get; set; }
    public string IncomingTargetLanguage { get; set; } = LanguageCode.SystemLanguage;

    public string? OutgoingSourceLanguage { get; set; } = LanguageCode.SystemLanguage;
    public string OutgoingTargetLanguage { get; set; } = LanguageCode.SystemDefaultTarget;

    public ProviderKind ProviderKind { get; set; } = ProviderKind.Azure;
    public bool OpenAtLogin { get; set; }

    public HotkeyChord TranslateOnlyHotkey { get; set; } = HotkeyChord.TranslateOnlyDefault;
    public HotkeyChord TranslateAndSendHotkey { get; set; } = HotkeyChord.TranslateAndSendDefault;
    public bool PopupModeEnabled { get; set; }
    public HotkeyChord PopupHotkey { get; set; } = HotkeyChord.PopupDefault;
    public bool ShowStatusHud { get; set; } = true;

    public bool DeepLUseFreeApi { get; set; } = true;

    public string OpenAIBaseUrl { get; set; } = "http://localhost:11434/v1";
    public string OpenAIModel { get; set; } = "local-model";

    public string AzureRegion { get; set; } = "global";

    public string CustomHttpUrl { get; set; } = "http://localhost:8080/translate";
    public string CustomHttpMethod { get; set; } = "POST";
    public string CustomHttpHeadersJson { get; set; } = """{"Content-Type":"application/json"}""";
    public string CustomHttpBodyTemplate { get; set; } =
        """{"text":"{{text}}","target":"{{to}}","source":"{{from}}"}""";
    public string CustomHttpResponsePath { get; set; } = "translatedText";

    public string? ResolvedSourceLanguage(bool outgoing)
    {
        var raw = outgoing ? OutgoingSourceLanguage : IncomingSourceLanguage;
        return string.IsNullOrWhiteSpace(raw) ? null : raw;
    }

    public string TargetLanguage(bool outgoing) =>
        outgoing ? OutgoingTargetLanguage : IncomingTargetLanguage;

    public string EngineLogDescription => ProviderKind switch
    {
        ProviderKind.Azure => $"{ProviderKind.DisplayName()} · region {AzureRegion}",
        ProviderKind.DeepL => $"{ProviderKind.DisplayName()} · {(DeepLUseFreeApi ? "free API" : "Pro API")}",
        ProviderKind.Google => ProviderKind.DisplayName(),
        ProviderKind.OpenAICompatible =>
            $"{ProviderKind.DisplayName()} · model {OpenAIModel} · {OpenAIBaseUrl}",
        ProviderKind.CustomHttp =>
            $"{ProviderKind.DisplayName()} · {CustomHttpMethod.ToUpperInvariant()} {CustomHttpUrl}",
        _ => ProviderKind.DisplayName(),
    };

    public void ResetHotkeysToDefaults()
    {
        TranslateOnlyHotkey = HotkeyChord.TranslateOnlyDefault;
        TranslateAndSendHotkey = HotkeyChord.TranslateAndSendDefault;
        PopupHotkey = HotkeyChord.PopupDefault;
    }

    public string? ModelFor(ProviderKind kind) => kind switch
    {
        ProviderKind.OpenAICompatible => OpenAIModel,
        _ => null,
    };

    public void SetModel(string model, ProviderKind kind)
    {
        if (kind == ProviderKind.OpenAICompatible)
            OpenAIModel = model;
    }

    public static AppSettings CreateDefaults() => new();
}

public sealed class AppSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private readonly string _path;

    public AppSettingsStore(string? path = null)
    {
        _path = path ?? DefaultPath();
    }

    public static string DefaultPath()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(root, "Prism", "settings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(_path))
                return AppSettings.CreateDefaults();

            var json = File.ReadAllText(_path);
            var dto = JsonSerializer.Deserialize<SettingsDto>(json, JsonOptions);
            return dto?.ToSettings() ?? AppSettings.CreateDefaults();
        }
        catch
        {
            return AppSettings.CreateDefaults();
        }
    }

    public void Save(AppSettings settings)
    {
        var dir = Path.GetDirectoryName(_path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        var dto = SettingsDto.From(settings);
        var json = JsonSerializer.Serialize(dto, JsonOptions);
        File.WriteAllText(_path, json);
    }

    private sealed class SettingsDto
    {
        public bool IsEnabled { get; set; } = true;
        public bool EnterTranslatesAndSends { get; set; }
        public string? IncomingSourceLanguage { get; set; }
        public string IncomingTargetLanguage { get; set; } = "en";
        public string? OutgoingSourceLanguage { get; set; }
        public string OutgoingTargetLanguage { get; set; } = "en";
        public string ProviderKind { get; set; } = "azure";
        public bool OpenAtLogin { get; set; }
        public HotkeyDto? TranslateOnlyHotkey { get; set; }
        public HotkeyDto? TranslateAndSendHotkey { get; set; }
        public bool PopupModeEnabled { get; set; }
        public HotkeyDto? PopupHotkey { get; set; }
        public bool ShowStatusHud { get; set; } = true;
        public bool DeepLUseFreeApi { get; set; } = true;
        public string OpenAIBaseUrl { get; set; } = "http://localhost:11434/v1";
        public string OpenAIModel { get; set; } = "local-model";
        public string AzureRegion { get; set; } = "global";
        public string CustomHttpUrl { get; set; } = "http://localhost:8080/translate";
        public string CustomHttpMethod { get; set; } = "POST";
        public string CustomHttpHeadersJson { get; set; } = """{"Content-Type":"application/json"}""";
        public string CustomHttpBodyTemplate { get; set; } =
            """{"text":"{{text}}","target":"{{to}}","source":"{{from}}"}""";
        public string CustomHttpResponsePath { get; set; } = "translatedText";

        public static SettingsDto From(AppSettings s) => new()
        {
            IsEnabled = s.IsEnabled,
            EnterTranslatesAndSends = s.EnterTranslatesAndSends,
            IncomingSourceLanguage = s.IncomingSourceLanguage,
            IncomingTargetLanguage = s.IncomingTargetLanguage,
            OutgoingSourceLanguage = s.OutgoingSourceLanguage,
            OutgoingTargetLanguage = s.OutgoingTargetLanguage,
            ProviderKind = s.ProviderKind.ToStorageKey(),
            OpenAtLogin = s.OpenAtLogin,
            TranslateOnlyHotkey = HotkeyDto.From(s.TranslateOnlyHotkey),
            TranslateAndSendHotkey = HotkeyDto.From(s.TranslateAndSendHotkey),
            PopupModeEnabled = s.PopupModeEnabled,
            PopupHotkey = HotkeyDto.From(s.PopupHotkey),
            ShowStatusHud = s.ShowStatusHud,
            DeepLUseFreeApi = s.DeepLUseFreeApi,
            OpenAIBaseUrl = s.OpenAIBaseUrl,
            OpenAIModel = s.OpenAIModel,
            AzureRegion = s.AzureRegion,
            CustomHttpUrl = s.CustomHttpUrl,
            CustomHttpMethod = s.CustomHttpMethod,
            CustomHttpHeadersJson = s.CustomHttpHeadersJson,
            CustomHttpBodyTemplate = s.CustomHttpBodyTemplate,
            CustomHttpResponsePath = s.CustomHttpResponsePath,
        };

        public AppSettings ToSettings() => new()
        {
            IsEnabled = IsEnabled,
            EnterTranslatesAndSends = EnterTranslatesAndSends,
            IncomingSourceLanguage = IncomingSourceLanguage,
            IncomingTargetLanguage = string.IsNullOrWhiteSpace(IncomingTargetLanguage)
                ? LanguageCode.SystemLanguage
                : IncomingTargetLanguage,
            OutgoingSourceLanguage = OutgoingSourceLanguage,
            OutgoingTargetLanguage = string.IsNullOrWhiteSpace(OutgoingTargetLanguage)
                ? LanguageCode.SystemDefaultTarget
                : OutgoingTargetLanguage,
            ProviderKind = ProviderKindExtensions.Parse(ProviderKind),
            OpenAtLogin = OpenAtLogin,
            TranslateOnlyHotkey = TranslateOnlyHotkey?.ToChord() ?? HotkeyChord.TranslateOnlyDefault,
            TranslateAndSendHotkey = TranslateAndSendHotkey?.ToChord() ?? HotkeyChord.TranslateAndSendDefault,
            PopupModeEnabled = PopupModeEnabled,
            PopupHotkey = PopupHotkey?.ToChord() ?? HotkeyChord.PopupDefault,
            ShowStatusHud = ShowStatusHud,
            DeepLUseFreeApi = DeepLUseFreeApi,
            OpenAIBaseUrl = OpenAIBaseUrl,
            OpenAIModel = OpenAIModel,
            AzureRegion = AzureRegion,
            CustomHttpUrl = CustomHttpUrl,
            CustomHttpMethod = CustomHttpMethod,
            CustomHttpHeadersJson = CustomHttpHeadersJson,
            CustomHttpBodyTemplate = CustomHttpBodyTemplate,
            CustomHttpResponsePath = CustomHttpResponsePath,
        };
    }

    private sealed class HotkeyDto
    {
        public int VirtualKey { get; set; }
        public byte Mods { get; set; }

        public static HotkeyDto From(HotkeyChord chord) => new()
        {
            VirtualKey = chord.VirtualKey,
            Mods = (byte)chord.Mods,
        };

        public HotkeyChord ToChord() => new()
        {
            VirtualKey = VirtualKey,
            Mods = (HotkeyChord.Modifiers)Mods,
        };
    }
}
