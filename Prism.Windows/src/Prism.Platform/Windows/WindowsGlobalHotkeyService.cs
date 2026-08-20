using Prism.Core.Hotkeys;
using Prism.Platform.Abstractions;

namespace Prism.Platform.Windows;

/// <summary>
/// Placeholder for the real Windows low-level keyboard hook.
/// Implement on a Windows machine with:
/// - SetWindowsHookEx(WH_KEYBOARD_LL)
/// - RegisterHotKey for chord registration (optional complement)
/// - SendInput inside WithInjection for synthetic Ctrl+C/V/A and Enter
/// </summary>
public sealed class WindowsGlobalHotkeyService : IGlobalHotkeyService
{
    public event Action? OnTranslateOnly;
    public event Action? OnTranslateAndSend;
    public event Action? OnPopup;
    public event Action? OnEnterTranslateAndSend;
    public event Action<bool>? OnTapStatusChange;

    public bool IsTapActive { get; private set; }

    private bool _enabled = true;
    private bool _enterTranslatesAndSends;
    private bool _popupModeEnabled;
    private bool _recording;
    private int _injectionDepth;
    private HotkeyChord _translateOnly = HotkeyChord.TranslateOnlyDefault;
    private HotkeyChord _translateAndSend = HotkeyChord.TranslateAndSendDefault;
    private HotkeyChord _popup = HotkeyChord.PopupDefault;

    public void UpdateConfiguration(
        bool enabled,
        bool enterTranslatesAndSends,
        HotkeyChord translateOnly,
        HotkeyChord translateAndSend,
        bool popupModeEnabled,
        HotkeyChord popup)
    {
        _enabled = enabled;
        _enterTranslatesAndSends = enterTranslatesAndSends;
        _translateOnly = translateOnly;
        _translateAndSend = translateAndSend;
        _popupModeEnabled = popupModeEnabled;
        _popup = popup;
    }

    public void SetRecordingHotkey(bool recording) => _recording = recording;

    public void Start()
    {
        // TODO(Windows): install WH_KEYBOARD_LL on a dedicated thread.
        IsTapActive = OperatingSystem.IsWindows();
        OnTapStatusChange?.Invoke(IsTapActive);
    }

    public void Stop()
    {
        IsTapActive = false;
        OnTapStatusChange?.Invoke(false);
    }

    public void WithInjection(Action work)
    {
        Interlocked.Increment(ref _injectionDepth);
        try { work(); }
        finally { Interlocked.Decrement(ref _injectionDepth); }
    }

    /// <summary>Test helper — simulate a key event through the matching logic.</summary>
    public bool TryHandleKey(int virtualKey, HotkeyChord.Modifiers mods)
    {
        if (!_enabled || _recording || _injectionDepth > 0)
            return false;

        if (_translateOnly.Matches(virtualKey, mods))
        {
            OnTranslateOnly?.Invoke();
            return true;
        }

        if (_translateAndSend.Matches(virtualKey, mods))
        {
            OnTranslateAndSend?.Invoke();
            return true;
        }

        if (_popupModeEnabled && _popup.Matches(virtualKey, mods))
        {
            OnPopup?.Invoke();
            return true;
        }

        if (_enterTranslatesAndSends
            && virtualKey is 0x0D or 0x6C
            && mods == HotkeyChord.Modifiers.None)
        {
            OnEnterTranslateAndSend?.Invoke();
            return true;
        }

        return false;
    }

    public void Dispose() => Stop();
}
