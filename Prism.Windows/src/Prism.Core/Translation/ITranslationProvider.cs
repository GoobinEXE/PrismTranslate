namespace Prism.Core.Translation;

public interface ITranslationProvider
{
    string Id { get; }
    string DisplayName { get; }
    Task<TranslationOutcome> TranslateAsync(string text, string? from, string to, CancellationToken cancellationToken = default);
}
