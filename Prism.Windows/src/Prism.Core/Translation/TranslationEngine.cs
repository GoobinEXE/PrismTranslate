using Prism.Core.Settings;
using Prism.Core.Translation;

namespace Prism.Core.Translation;

public interface ILanguageDetector
{
    string? Detect(string text);
}

/// <summary>
/// Lightweight heuristic detector used when a provider does not report source language.
/// Platform layer may wrap Windows.Globalization for better accuracy.
/// </summary>
public sealed class HeuristicLanguageDetector : ILanguageDetector
{
    public string? Detect(string text)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Trim().Length < 3)
            return null;

        // Defer to culture-insensitive heuristics; platform can replace this.
        return null;
    }
}

public sealed class TranslationEngine
{
    private readonly Func<AppSettings, ITranslationProvider> _providerFactory;
    private readonly ILanguageDetector _detector;
    private AppSettings _settings;

    private readonly List<CacheKey> _cacheOrder = [];
    private readonly Dictionary<CacheKey, TranslationOutcome> _cacheValues = new();
    private const int MaxCacheEntries = 64;

    private readonly record struct CacheKey(string Text, string? From, string To, string Engine);

    public TranslationEngine(
        AppSettings settings,
        Func<AppSettings, ITranslationProvider> providerFactory,
        ILanguageDetector? detector = null)
    {
        _settings = settings;
        _providerFactory = providerFactory;
        _detector = detector ?? new HeuristicLanguageDetector();
    }

    public void UpdateSettings(AppSettings settings)
    {
        var providerChanged = settings.ProviderKind != _settings.ProviderKind;
        var engineChanged = settings.EngineLogDescription != _settings.EngineLogDescription;
        var languagesChanged =
            settings.IncomingSourceLanguage != _settings.IncomingSourceLanguage
            || settings.IncomingTargetLanguage != _settings.IncomingTargetLanguage
            || settings.OutgoingSourceLanguage != _settings.OutgoingSourceLanguage
            || settings.OutgoingTargetLanguage != _settings.OutgoingTargetLanguage;

        _settings = settings;
        if (providerChanged || engineChanged || languagesChanged)
            ClearCache();
    }

    public async Task<TranslationOutcome> TranslateAsync(
        string text,
        string? from,
        string to,
        CancellationToken cancellationToken = default)
    {
        var key = new CacheKey(text, from, to, _settings.EngineLogDescription);
        if (_cacheValues.TryGetValue(key, out var cached))
        {
            TouchCache(key);
            return cached;
        }

        var provider = _providerFactory(_settings);
        var outcome = await provider.TranslateAsync(text, from, to, cancellationToken).ConfigureAwait(false);

        if (outcome.DetectedSourceLanguage is null)
        {
            var detected = _detector.Detect(text);
            if (detected is not null)
                outcome = outcome with { DetectedSourceLanguage = LanguageCode.Normalize(detected) };
        }

        PutCache(key, outcome);
        return outcome;
    }

    public void ClearCache()
    {
        _cacheOrder.Clear();
        _cacheValues.Clear();
    }

    private void TouchCache(CacheKey key)
    {
        _cacheOrder.Remove(key);
        _cacheOrder.Add(key);
    }

    private void PutCache(CacheKey key, TranslationOutcome value)
    {
        if (_cacheValues.ContainsKey(key))
        {
            TouchCache(key);
            _cacheValues[key] = value;
            return;
        }

        _cacheValues[key] = value;
        _cacheOrder.Add(key);
        while (_cacheOrder.Count > MaxCacheEntries)
        {
            var oldest = _cacheOrder[0];
            _cacheOrder.RemoveAt(0);
            _cacheValues.Remove(oldest);
        }
    }
}
