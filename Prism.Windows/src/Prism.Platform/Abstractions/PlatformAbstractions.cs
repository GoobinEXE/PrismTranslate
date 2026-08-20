using Prism.Core.Hotkeys;
using Prism.Core.Orchestration;
using Prism.Core.TextIO;

namespace Prism.Platform.Abstractions;

public interface IGlobalHotkeyService : IDisposable
{
    event Action? OnTranslateOnly;
    event Action? OnTranslateAndSend;
    event Action? OnPopup;
    event Action? OnEnterTranslateAndSend;
    event Action<bool>? OnTapStatusChange;

    bool IsTapActive { get; }

    void UpdateConfiguration(
        bool enabled,
        bool enterTranslatesAndSends,
        HotkeyChord translateOnly,
        HotkeyChord translateAndSend,
        bool popupModeEnabled,
        HotkeyChord popup);

    void SetRecordingHotkey(bool recording);
    void Start();
    void Stop();
    void WithInjection(Action work);
}

public interface ICredentialStore
{
    void Save(string key, string secret);
    string? Load(string key);
    void Delete(string key);
}

public interface IStartupRegistration
{
    Task SetEnabledAsync(bool enabled);
    Task<bool> IsEnabledAsync();
}

public interface IPermissionsService
{
    bool IsAccessibilityAvailable();
    void OpenAccessibilitySettings();
}

/// <summary>
/// Stub implementations for non-Windows CI / Linux development hosts.
/// Real Windows implementations live behind #if WINDOWS / separate WinUI host.
/// </summary>
public sealed class StubFocusedTextService : IFocusedTextService
{
    public string? NextText { get; set; }
    public bool NextIsEditable { get; set; } = true;
    public string? LastReplacedText { get; private set; }

    public Task<FocusedTextCapture> SelectAndReadFocusedTextAsync(
        bool preferReplaceInPlace,
        bool allowSelectAllWhenEditable,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrEmpty(NextText))
            throw FocusedTextIoException.NoFocusedElement();

        return Task.FromResult(new FocusedTextCapture(
            NextText,
            DidSelectAll: true,
            UsedClipboardForRead: false,
            IsEditable: NextIsEditable));
    }

    public Task ReplaceSelectionAsync(FocusedTextCapture capture, string text, CancellationToken cancellationToken = default)
    {
        LastReplacedText = text;
        return Task.CompletedTask;
    }

    public void FinishClipboardSession(bool onlyIfUnchanged = false) { }

    public bool IsFocusedTextEditable() => NextIsEditable;
}

public sealed class StubForegroundAppService : IForegroundAppService
{
    public string? GetForegroundAppId() => "stub";
    public string? GetForegroundAppName() => "Stub App";
    public Task ReactivateAsync(string? appId, CancellationToken cancellationToken = default) => Task.CompletedTask;
}

public sealed class StubKeyboardSimulator : IKeyboardSimulator
{
    public int ReturnPressCount { get; private set; }
    public void PressReturn() => ReturnPressCount++;
}

public sealed class StubTranslationResultPresenter : ITranslationResultPresenter
{
    public TranslationPanelRequest? LastRequest { get; private set; }
    public bool IsVisible { get; private set; }

    public Task ShowAsync(
        TranslationPanelRequest request,
        Func<FocusedTextCapture, string, string?, Task>? onReplace = null,
        Action? onDismissWithoutReplace = null)
    {
        LastRequest = request;
        IsVisible = true;
        return Task.CompletedTask;
    }

    public void Dismiss() => IsVisible = false;
}

public sealed class InMemoryCredentialStore : ICredentialStore
{
    private readonly Dictionary<string, string> _store = new(StringComparer.OrdinalIgnoreCase);

    public void Save(string key, string secret) => _store[key] = secret;
    public string? Load(string key) => _store.TryGetValue(key, out var v) ? v : null;
    public void Delete(string key) => _store.Remove(key);
}
