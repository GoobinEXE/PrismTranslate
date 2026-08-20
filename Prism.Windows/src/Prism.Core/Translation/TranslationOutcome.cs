namespace Prism.Core.Translation;

public sealed record TranslationOutcome(string Text, string? DetectedSourceLanguage = null);
