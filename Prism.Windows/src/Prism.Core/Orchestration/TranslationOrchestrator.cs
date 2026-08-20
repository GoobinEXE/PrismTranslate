using Prism.Core.Policy;
using Prism.Core.Settings;
using Prism.Core.TextIO;
using Prism.Core.Translation;

namespace Prism.Core.Orchestration;

public enum AppStatusKind
{
    Idle,
    Translating,
    Success,
    Error,
}

public sealed record AppStatus(AppStatusKind Kind, string? Message = null)
{
    public static AppStatus Idle { get; } = new(AppStatusKind.Idle);
    public static AppStatus Translating { get; } = new(AppStatusKind.Translating);
    public static AppStatus Success { get; } = new(AppStatusKind.Success);
    public static AppStatus Error(string message) => new(AppStatusKind.Error, message);
}

public sealed record TranslationPanelRequest(
    string Original,
    string Translated,
    bool CanReplace,
    bool ShowOriginal,
    string SourceLanguageLabel,
    string TargetLanguageLabel,
    string PairContextLabel,
    FocusedTextCapture Capture,
    string? TargetAppId);

public interface IFocusedTextService
{
    Task<FocusedTextCapture> SelectAndReadFocusedTextAsync(
        bool preferReplaceInPlace,
        bool allowSelectAllWhenEditable,
        CancellationToken cancellationToken = default);

    Task ReplaceSelectionAsync(FocusedTextCapture capture, string text, CancellationToken cancellationToken = default);

    void FinishClipboardSession(bool onlyIfUnchanged = false);

    bool IsFocusedTextEditable();
}

public interface IForegroundAppService
{
    string? GetForegroundAppId();
    string? GetForegroundAppName();
    Task ReactivateAsync(string? appId, CancellationToken cancellationToken = default);
}

public interface IKeyboardSimulator
{
    void PressReturn();
}

public interface ITranslationResultPresenter
{
    Task ShowAsync(TranslationPanelRequest request, Func<FocusedTextCapture, string, string?, Task>? onReplace = null, Action? onDismissWithoutReplace = null);
    bool IsVisible { get; }
}

/// <summary>
/// Port of macOS TranslationOrchestrator — capture → pair selection → translate → panel or replace.
/// </summary>
public sealed class TranslationOrchestrator
{
    private static readonly TimeSpan MaxRunDuration = TimeSpan.FromSeconds(45);

    private AppSettings _settings;
    private readonly TranslationEngine _engine;
    private readonly IFocusedTextService _textIo;
    private readonly IForegroundAppService _foreground;
    private readonly IKeyboardSimulator _keyboard;
    private readonly ITranslationResultPresenter? _panel;
    private readonly ILanguageDetector _detector;

    private bool _isRunning;
    private DateTime? _runStartUtc;

    public bool IsBusy => _isRunning;
    public Action<AppStatus>? OnStatusChange { get; set; }
    public Action? PressReturnHandler { get; set; }

    public TranslationOrchestrator(
        AppSettings settings,
        TranslationEngine engine,
        IFocusedTextService textIo,
        IForegroundAppService foreground,
        IKeyboardSimulator keyboard,
        ITranslationResultPresenter? panel = null,
        ILanguageDetector? detector = null)
    {
        _settings = settings;
        _engine = engine;
        _textIo = textIo;
        _foreground = foreground;
        _keyboard = keyboard;
        _panel = panel;
        _detector = detector ?? new HeuristicLanguageDetector();
    }

    public void UpdateSettings(AppSettings settings) => _settings = settings;

    public async Task TranslateFocusedTextAsync(
        TranslationPresentation presentation,
        TranslationTrigger trigger,
        CancellationToken cancellationToken = default)
    {
        if (!_settings.IsEnabled)
        {
            OnStatusChange?.Invoke(AppStatus.Error("Prism is off — turn it on in Settings"));
            return;
        }

        if (_isRunning && _runStartUtc is { } start)
        {
            if (DateTime.UtcNow - start > MaxRunDuration)
            {
                _isRunning = false;
                _runStartUtc = null;
            }
        }

        if (_isRunning)
        {
            OnStatusChange?.Invoke(AppStatus.Error("Previous translation still running — wait"));
            return;
        }

        var targetAppId = _foreground.GetForegroundAppId();
        _isRunning = true;
        _runStartUtc = DateTime.UtcNow;
        var holdClipboardForPanel = false;

        try
        {
            OnStatusChange?.Invoke(AppStatus.Translating);

            var preferReplaceInPlace = presentation.Kind == TranslationPresentationKind.ReplaceInPlace;
            var capture = await _textIo.SelectAndReadFocusedTextAsync(
                preferReplaceInPlace,
                allowSelectAllWhenEditable: true,
                cancellationToken).ConfigureAwait(false);

            var trimmed = capture.Text.Trim();
            if (string.IsNullOrEmpty(trimmed))
            {
                OnStatusChange?.Invoke(AppStatus.Error("No text in the focused field"));
                return;
            }

            var incomingFrom = _settings.ResolvedSourceLanguage(outgoing: false);
            var incomingTo = _settings.IncomingTargetLanguage;
            var outgoingFrom = _settings.ResolvedSourceLanguage(outgoing: true);
            var outgoingTo = _settings.OutgoingTargetLanguage;
            var detected = _detector.Detect(trimmed);

            var usedOutgoingPair = capture.IsEditable;
            if (!capture.IsEditable
                && detected is not null
                && LanguageCode.Normalize(detected) == LanguageCode.Normalize(incomingTo)
                && LanguageCode.Normalize(outgoingTo) != LanguageCode.Normalize(incomingTo))
            {
                usedOutgoingPair = true;
            }

            var from = usedOutgoingPair ? outgoingFrom : incomingFrom;
            var to = usedOutgoingPair ? outgoingTo : incomingTo;

            TranslationOutcome outcome;
            try
            {
                outcome = await _engine.TranslateAsync(trimmed, from, to, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex) when (
                !usedOutgoingPair
                && LanguageCode.Normalize(outgoingTo) != LanguageCode.Normalize(incomingTo)
                && IsUnsupportedPair(ex))
            {
                from = outgoingFrom;
                to = outgoingTo;
                usedOutgoingPair = true;
                outcome = await _engine.TranslateAsync(trimmed, from, to, cancellationToken).ConfigureAwait(false);
            }

            var output = PreserveSurroundingWhitespace(capture.Text, outcome.Text);
            var action = TranslationActionPolicy.Resolve(presentation, capture);

            if (action.ShowPanel)
            {
                var sourceLabel = from is not null
                    ? LanguageCode.DisplayNameFor(from)
                    : outcome.DetectedSourceLanguage is not null
                        ? LanguageCode.DisplayNameFor(outcome.DetectedSourceLanguage)
                        : LanguageCode.DisplayNameFor(LanguageCode.SystemLanguage);
                var targetLabel = LanguageCode.DisplayNameFor(to);

                holdClipboardForPanel = true;
                if (_panel is not null)
                {
                    await _panel.ShowAsync(
                        new TranslationPanelRequest(
                            Original: capture.Text,
                            Translated: output,
                            CanReplace: action.CanReplace,
                            ShowOriginal: action.CanReplace,
                            SourceLanguageLabel: sourceLabel,
                            TargetLanguageLabel: targetLabel,
                            PairContextLabel: usedOutgoingPair ? "Text I write" : "Text I read",
                            Capture: capture,
                            TargetAppId: targetAppId),
                        onReplace: async (cap, text, appId) =>
                            await PerformReplaceFromPanelAsync(cap, text, appId, cancellationToken).ConfigureAwait(false),
                        onDismissWithoutReplace: () => _textIo.FinishClipboardSession(onlyIfUnchanged: true)).ConfigureAwait(false);
                }

                OnStatusChange?.Invoke(AppStatus.Success);
                return;
            }

            await PerformReplaceAsync(capture, output, targetAppId, cancellationToken).ConfigureAwait(false);

            if (action.SendAfter)
            {
                await Task.Delay(25, cancellationToken).ConfigureAwait(false);
                if (PressReturnHandler is not null)
                    PressReturnHandler();
                else
                    _keyboard.PressReturn();
            }

            OnStatusChange?.Invoke(AppStatus.Success);
        }
        catch (Exception ex)
        {
            OnStatusChange?.Invoke(AppStatus.Error(ex.Message));
        }
        finally
        {
            _isRunning = false;
            _runStartUtc = null;
            if (!holdClipboardForPanel)
                _textIo.FinishClipboardSession();
        }
    }

    private async Task PerformReplaceFromPanelAsync(
        FocusedTextCapture capture,
        string text,
        string? targetAppId,
        CancellationToken cancellationToken)
    {
        if (_isRunning && _runStartUtc is { } start && DateTime.UtcNow - start > MaxRunDuration)
        {
            _isRunning = false;
            _runStartUtc = null;
        }

        if (_isRunning)
        {
            OnStatusChange?.Invoke(AppStatus.Error("Previous translation still running — wait"));
            return;
        }

        _isRunning = true;
        _runStartUtc = DateTime.UtcNow;
        try
        {
            await PerformReplaceAsync(capture, text, targetAppId, cancellationToken).ConfigureAwait(false);
            OnStatusChange?.Invoke(AppStatus.Success);
        }
        catch (Exception ex)
        {
            OnStatusChange?.Invoke(AppStatus.Error(ex.Message));
        }
        finally
        {
            _isRunning = false;
            _runStartUtc = null;
            _textIo.FinishClipboardSession();
        }
    }

    private async Task PerformReplaceAsync(
        FocusedTextCapture capture,
        string text,
        string? targetAppId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(text))
            throw TranslationError.EmptyResponse();

        await _foreground.ReactivateAsync(targetAppId, cancellationToken).ConfigureAwait(false);
        await _textIo.ReplaceSelectionAsync(capture, text, cancellationToken).ConfigureAwait(false);
    }

    private static bool IsUnsupportedPair(Exception ex) =>
        ex is TranslationError te && te.IsUnsupportedLanguagePair;

    internal static string PreserveSurroundingWhitespace(string original, string translated)
    {
        var leadingLen = 0;
        while (leadingLen < original.Length && char.IsWhiteSpace(original[leadingLen]))
            leadingLen++;

        var trailingLen = 0;
        while (trailingLen < original.Length - leadingLen
               && char.IsWhiteSpace(original[original.Length - 1 - trailingLen]))
            trailingLen++;

        var leading = original[..leadingLen];
        var trailing = trailingLen > 0 ? original[^trailingLen..] : "";
        return leading + translated.Trim() + trailing;
    }
}
