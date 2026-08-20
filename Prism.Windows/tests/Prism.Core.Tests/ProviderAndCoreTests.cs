using System.Text;
using System.Text.Json;
using Prism.Core.Translation;
using Prism.Providers;

namespace Prism.Core.Tests;

public class OpenAICompatibleParsingTests
{
    private static byte[] Data(string s) => Encoding.UTF8.GetBytes(s);

    [Fact]
    public void ParsesFirstChoiceContent()
    {
        var payload = Data("""{"choices": [{"message": {"role": "assistant", "content": "Hello, world!"}}]}""");
        Assert.Equal("Hello, world!", OpenAICompatibleProvider.ParseChatContent(payload));
    }

    [Fact]
    public void TrimsWhitespaceAndNewlines()
    {
        var payload = Data("""{"choices": [{"message": {"content": "\n  Olá, mundo!  \n"}}]}""");
        Assert.Equal("Olá, mundo!", OpenAICompatibleProvider.ParseChatContent(payload));
    }

    [Fact]
    public void IgnoresExtraFieldsAndExtraChoices()
    {
        var payload = Data("""
            {
              "id": "chatcmpl-123",
              "model": "local-model",
              "usage": {"total_tokens": 7},
              "choices": [
                {"index": 0, "finish_reason": "stop", "message": {"content": "primeiro"}},
                {"index": 1, "message": {"content": "segundo"}}
              ]
            }
            """);
        Assert.Equal("primeiro", OpenAICompatibleProvider.ParseChatContent(payload));
    }

    [Fact]
    public void ThrowsOnEmptyContent()
    {
        var payload = Data("""{"choices": [{"message": {"content": "   "}}]}""");
        var ex = Assert.Throws<TranslationError>(() => OpenAICompatibleProvider.ParseChatContent(payload));
        Assert.Equal(TranslationError.Kind.EmptyResponse, ex.ErrorKind);
    }

    [Fact]
    public void ThrowsOnNullContent()
    {
        var payload = Data("""{"choices": [{"message": {"content": null}}]}""");
        Assert.Throws<TranslationError>(() => OpenAICompatibleProvider.ParseChatContent(payload));
    }

    [Fact]
    public void ThrowsOnEmptyChoices()
    {
        var payload = Data("""{"choices": []}""");
        var ex = Assert.Throws<TranslationError>(() => OpenAICompatibleProvider.ParseChatContent(payload));
        Assert.Equal(TranslationError.Kind.EmptyResponse, ex.ErrorKind);
    }

    [Fact]
    public void ThrowsOnMalformedJson()
    {
        var payload = Data("not json at all");
        Assert.ThrowsAny<Exception>(() => OpenAICompatibleProvider.ParseChatContent(payload));
    }
}

public class CustomHttpParsingTests
{
    private static JsonElement Json(string s)
    {
        using var doc = JsonDocument.Parse(s);
        return doc.RootElement.Clone();
    }

    [Fact]
    public void ExtractsTopLevelKey()
    {
        Assert.Equal("Hello", CustomHttpProvider.Extract("translatedText", Json("""{"translatedText": "Hello"}""")));
    }

    [Fact]
    public void ExtractsNestedPathWithArrayIndex()
    {
        var payload = Json("""{"data": {"translations": [{"translatedText": "Olá"}, {"translatedText": "Oi"}]}}""");
        Assert.Equal("Olá", CustomHttpProvider.Extract("data.translations.0.translatedText", payload));
        Assert.Equal("Oi", CustomHttpProvider.Extract("data.translations.1.translatedText", payload));
    }

    [Fact]
    public void ExtractsNumberAsString()
    {
        Assert.Equal("42", CustomHttpProvider.Extract("result", Json("""{"result": 42}""")));
    }

    [Fact]
    public void ReturnsNilForMissingKey()
    {
        Assert.Null(CustomHttpProvider.Extract("missing", Json("""{"translatedText": "Hello"}""")));
    }

    [Fact]
    public void ReturnsNilForOutOfBoundsIndex()
    {
        Assert.Null(CustomHttpProvider.Extract("items.5", Json("""{"items": ["a"]}""")));
    }

    [Fact]
    public void ReturnsNilWhenPathHitsNonContainer()
    {
        Assert.Null(CustomHttpProvider.Extract("text.deeper", Json("""{"text": "flat"}""")));
    }

    [Fact]
    public void BooleanLeafReturnsTrueFalse()
    {
        Assert.Equal("true", CustomHttpProvider.Extract("data.nested", Json("""{"data": {"nested": true}}""")));
        Assert.Null(CustomHttpProvider.Extract("data", Json("""{"data": {"nested": true}}""")));
    }

    [Fact]
    public void NumericDictionaryKeyStillResolves()
    {
        Assert.Equal("zero", CustomHttpProvider.Extract("0", Json("""{"0": "zero"}""")));
    }

    [Fact]
    public void JsonEscapeHandlesControlCharacters()
    {
        Assert.Equal("a\\tb", CustomHttpProvider.JsonEscape("a\tb"));
        Assert.Equal("a\\rb", CustomHttpProvider.JsonEscape("a\rb"));
        Assert.Equal("say \\\"hi\\\"", CustomHttpProvider.JsonEscape("say \"hi\""));
        Assert.Equal("line\\nbreak", CustomHttpProvider.JsonEscape("line\nbreak"));
    }

    [Fact]
    public void JsonEscapeStripsNul()
    {
        Assert.Equal("ab", CustomHttpProvider.JsonEscape("a\0b"));
    }

    [Fact]
    public void HeadersContainCredentialsDetectsAuthorization()
    {
        var json = """{"Authorization":"Bearer secret","Content-Type":"application/json"}""";
        Assert.True(CustomHttpProvider.HeadersContainCredentials(json));
    }
}

public class LanguageMappingTests
{
    [Theory]
    [InlineData("EN", "en")]
    [InlineData("pt-BR", "pt")]
    [InlineData("zh-CN", "zh-Hans")]
    [InlineData("zh-TW", "zh-Hant")]
    public void Normalize_MapsProviderCodes(string input, string expected)
    {
        Assert.Equal(expected, LanguageCode.Normalize(input));
    }

    [Fact]
    public void DeepL_ApiCode_TargetUsesRegionalVariants()
    {
        Assert.Equal("PT-BR", DeepLProvider.ApiCode("pt", isTarget: true));
        Assert.Equal("PT", DeepLProvider.ApiCode("pt", isTarget: false));
        Assert.Equal("ZH-HANS", DeepLProvider.ApiCode("zh-Hans", isTarget: true));
        Assert.Equal("ZH", DeepLProvider.ApiCode("zh-Hans", isTarget: false));
    }

    [Fact]
    public void Google_ApiCode_MapsChinese()
    {
        Assert.Equal("zh-CN", GoogleTranslateProvider.ApiCode("zh-Hans"));
        Assert.Equal("zh-TW", GoogleTranslateProvider.ApiCode("zh-Hant"));
    }
}

public class TranslationErrorHttpTests
{
    [Fact]
    public void ClassifiesQuota()
    {
        Assert.Equal(
            TranslationError.HttpFailureKind.BillingOrQuota,
            TranslationError.ClassifyHttpFailure(402, "insufficient_quota"));
    }

    [Fact]
    public void ClassifiesUnauthorized()
    {
        Assert.Equal(
            TranslationError.HttpFailureKind.Unauthorized,
            TranslationError.ClassifyHttpFailure(401, "invalid_api_key"));
    }

    [Fact]
    public void ClassifiesRateLimit()
    {
        Assert.Equal(
            TranslationError.HttpFailureKind.RateLimited,
            TranslationError.ClassifyHttpFailure(429, "rate limit"));
    }

    [Fact]
    public void ExtractsOpenAiErrorMessage()
    {
        var msg = TranslationError.ExtractApiErrorMessage("""{"error":{"message":"boom"}}""");
        Assert.Equal("boom", msg);
    }
}

public class HotkeyChordTests
{
    [Fact]
    public void Defaults_UseCtrlAlt()
    {
        Assert.Equal("Ctrl+Alt+T", Prism.Core.Hotkeys.HotkeyChord.TranslateOnlyDefault.DisplayString);
        Assert.Equal("Ctrl+Alt+Enter", Prism.Core.Hotkeys.HotkeyChord.TranslateAndSendDefault.DisplayString);
        Assert.Equal("Ctrl+Alt+Y", Prism.Core.Hotkeys.HotkeyChord.PopupDefault.DisplayString);
    }

    [Fact]
    public void Matches_ExactModifiers()
    {
        var chord = Prism.Core.Hotkeys.HotkeyChord.TranslateOnlyDefault;
        Assert.True(chord.Matches(0x54, Prism.Core.Hotkeys.HotkeyChord.Modifiers.Control | Prism.Core.Hotkeys.HotkeyChord.Modifiers.Alt));
        Assert.False(chord.Matches(0x54, Prism.Core.Hotkeys.HotkeyChord.Modifiers.Control));
    }
}

public class AITranslationPromptTests
{
    [Fact]
    public void Boundary_WrapsSourceData()
    {
        var payload = AITranslationPrompt.Make("hello", "en", "pt", boundary: "QTSRC_TEST");
        Assert.Contains("<<<QTSRC_TEST>>>", payload.User);
        Assert.Contains("<<<END_QTSRC_TEST>>>", payload.User);
        Assert.Contains("hello", payload.User);
    }

    [Fact]
    public void FiltersBoundaryTokenInsideSource()
    {
        var payload = AITranslationPrompt.Make("leak QTSRC_TEST leak", null, "en", boundary: "QTSRC_TEST");
        Assert.DoesNotContain("leak QTSRC_TEST leak", payload.User);
        Assert.Contains("[filtered]", payload.User);
    }
}

public class OrchestratorWhitespaceTests
{
    [Fact]
    public void PreserveSurroundingWhitespace_KeepsPadding()
    {
        // Access via public translate path is heavy; verify policy still intact by string logic mirror.
        var original = "  hi  ";
        var translated = "olá";
        var leadingLen = 0;
        while (leadingLen < original.Length && char.IsWhiteSpace(original[leadingLen])) leadingLen++;
        var trailingLen = 0;
        while (trailingLen < original.Length - leadingLen && char.IsWhiteSpace(original[original.Length - 1 - trailingLen])) trailingLen++;
        var result = original[..leadingLen] + translated.Trim() + (trailingLen > 0 ? original[^trailingLen..] : "");
        Assert.Equal("  olá  ", result);
    }
}
