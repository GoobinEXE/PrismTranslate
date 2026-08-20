using Prism.Core.Orchestration;
using Prism.Core.Policy;
using Prism.Core.Settings;
using Prism.Core.Translation;
using Prism.Platform.Abstractions;

namespace Prism.Core.Tests;

public class TranslationOrchestratorIntegrationTests
{
    private sealed class FakeProvider : ITranslationProvider
    {
        public string Id => "fake";
        public string DisplayName => "Fake";
        public string? LastFrom { get; private set; }
        public string? LastTo { get; private set; }

        public Task<TranslationOutcome> TranslateAsync(
            string text,
            string? from,
            string to,
            CancellationToken cancellationToken = default)
        {
            LastFrom = from;
            LastTo = to;
            return Task.FromResult(new TranslationOutcome($"[{to}]{text}", from));
        }
    }

    [Fact]
    public async Task EditableField_UsesOutgoingPair_AndReplacesInPlace()
    {
        var settings = new AppSettings
        {
            IsEnabled = true,
            IncomingSourceLanguage = null,
            IncomingTargetLanguage = "pt",
            OutgoingSourceLanguage = "pt",
            OutgoingTargetLanguage = "en",
        };
        var fake = new FakeProvider();
        var engine = new TranslationEngine(settings, _ => fake);
        var textIo = new StubFocusedTextService { NextText = "olá", NextIsEditable = true };
        var panel = new StubTranslationResultPresenter();
        var keyboard = new StubKeyboardSimulator();
        var orchestrator = new TranslationOrchestrator(
            settings,
            engine,
            textIo,
            new StubForegroundAppService(),
            keyboard,
            panel);

        AppStatus? last = null;
        orchestrator.OnStatusChange = s => last = s;

        await orchestrator.TranslateFocusedTextAsync(
            TranslationPresentation.ReplaceInPlace(sendAfter: false),
            new TranslationTrigger(TranslationTriggerKind.HotkeyTranslateOnly, "Ctrl+Alt+T"));

        Assert.Equal(AppStatusKind.Success, last?.Kind);
        Assert.Equal("en", fake.LastTo);
        Assert.Equal("[en]olá", textIo.LastReplacedText);
        Assert.False(panel.IsVisible);
    }

    [Fact]
    public async Task ReadOnlyField_UsesIncomingPair_AndShowsPanel()
    {
        var settings = new AppSettings
        {
            IsEnabled = true,
            IncomingSourceLanguage = null,
            IncomingTargetLanguage = "pt",
            OutgoingSourceLanguage = "pt",
            OutgoingTargetLanguage = "en",
        };
        var fake = new FakeProvider();
        var engine = new TranslationEngine(settings, _ => fake);
        var textIo = new StubFocusedTextService { NextText = "hello", NextIsEditable = false };
        var panel = new StubTranslationResultPresenter();
        var orchestrator = new TranslationOrchestrator(
            settings,
            engine,
            textIo,
            new StubForegroundAppService(),
            new StubKeyboardSimulator(),
            panel);

        await orchestrator.TranslateFocusedTextAsync(
            TranslationPresentation.ReplaceInPlace(sendAfter: false),
            new TranslationTrigger(TranslationTriggerKind.HotkeyTranslateOnly, "Ctrl+Alt+T"));

        Assert.Equal("pt", fake.LastTo);
        Assert.True(panel.IsVisible);
        Assert.NotNull(panel.LastRequest);
        Assert.False(panel.LastRequest!.CanReplace);
        Assert.Equal("Text I read", panel.LastRequest.PairContextLabel);
    }

    [Fact]
    public async Task DisabledApp_ReportsError()
    {
        var settings = new AppSettings { IsEnabled = false };
        var engine = new TranslationEngine(settings, _ => new FakeProvider());
        var orchestrator = new TranslationOrchestrator(
            settings,
            engine,
            new StubFocusedTextService { NextText = "x", NextIsEditable = true },
            new StubForegroundAppService(),
            new StubKeyboardSimulator());

        AppStatus? last = null;
        orchestrator.OnStatusChange = s => last = s;

        await orchestrator.TranslateFocusedTextAsync(
            TranslationPresentation.ReplaceInPlace(),
            new TranslationTrigger(TranslationTriggerKind.HotkeyTranslateOnly, "Ctrl+Alt+T"));

        Assert.Equal(AppStatusKind.Error, last?.Kind);
        Assert.Contains("off", last?.Message, StringComparison.OrdinalIgnoreCase);
    }
}
