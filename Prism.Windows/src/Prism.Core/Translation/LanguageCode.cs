namespace Prism.Core.Translation;

public sealed record LanguageCode(string Id, string DisplayName)
{
    public string id => Id;

    public static IReadOnlyList<LanguageCode> CommonTargets { get; } =
    [
        new("en", "English"),
        new("pt", "Português"),
        new("es", "Español"),
        new("fr", "Français"),
        new("de", "Deutsch"),
        new("it", "Italiano"),
        new("ja", "日本語"),
        new("ko", "한국어"),
        new("zh-Hans", "中文 (简体)"),
        new("zh-Hant", "中文 (繁體)"),
        new("ru", "Русский"),
        new("ar", "العربية"),
        new("nl", "Nederlands"),
        new("pl", "Polski"),
        new("tr", "Türkçe"),
        new("hi", "हिन्दी"),
    ];

    public static string DisplayNameFor(string id)
    {
        var normalized = Normalize(id);
        var known = CommonTargets.FirstOrDefault(c => c.Id == normalized);
        if (known is not null) return known.DisplayName;

        try
        {
            var culture = new System.Globalization.CultureInfo(normalized);
            return culture.DisplayName;
        }
        catch (System.Globalization.CultureNotFoundException)
        {
            return id;
        }
    }

    public static string PairLabel(string? from, string to)
    {
        var source = from is null ? "automatic detection" : DisplayNameFor(from);
        return $"{source} → {DisplayNameFor(to)}";
    }

    public static string Normalize(string code)
    {
        var lower = code.Trim().ToLowerInvariant().Replace('_', '-');
        return lower switch
        {
            "en" or "en-us" or "en-gb" => "en",
            "pt" or "pt-br" or "pt-pt" => "pt",
            "zh" or "zh-cn" or "zh-hans" or "zh-hans-cn" => "zh-Hans",
            "zh-tw" or "zh-hk" or "zh-hant" or "zh-hant-tw" => "zh-Hant",
            _ when CommonTargets.Any(c => c.Id == lower) => lower,
            _ => TryBaseLanguage(lower),
        };
    }

    private static string TryBaseLanguage(string lower)
    {
        try
        {
            var baseCode = new System.Globalization.CultureInfo(lower).TwoLetterISOLanguageName;
            if (CommonTargets.Any(c => c.Id == baseCode))
                return baseCode;
        }
        catch (System.Globalization.CultureNotFoundException)
        {
            // fall through
        }

        var dash = lower.IndexOf('-');
        if (dash > 0)
        {
            var basePart = lower[..dash];
            if (CommonTargets.Any(c => c.Id == basePart))
                return basePart;
        }

        return lower;
    }

    public static string SystemLanguage
    {
        get
        {
            var preferred = System.Globalization.CultureInfo.CurrentUICulture;
            var code = preferred.TwoLetterISOLanguageName;
            if (CommonTargets.Any(c => c.Id == code))
                return code;

            if (code == "zh")
            {
                var name = preferred.Name.ToLowerInvariant();
                return name.Contains("hant") || name.Contains("tw") || name.Contains("hk")
                    ? "zh-Hant"
                    : "zh-Hans";
            }

            return "en";
        }
    }

    public static string SystemDefaultTarget => SystemLanguage == "en" ? "pt" : "en";
}
