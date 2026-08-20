using Prism.Core.Orchestration;
using Prism.Core.TextIO;

namespace Prism.Platform.Windows;

/// <summary>
/// Skeleton for UI Automation + clipboard capture/replace.
/// Full implementation requires Windows (UIAutomationClient / FlaUI or raw COM).
/// </summary>
public sealed class WindowsFocusedTextService : IFocusedTextService
{
    public Task<FocusedTextCapture> SelectAndReadFocusedTextAsync(
        bool preferReplaceInPlace,
        bool allowSelectAllWhenEditable,
        CancellationToken cancellationToken = default)
    {
        if (!OperatingSystem.IsWindows())
            throw FocusedTextIoException.AccessibilityDenied();

        // TODO(Windows):
        // 1. IUIAutomation.GetFocusedElement
        // 2. Walk ancestors for Edit/Document + ValuePattern/TextPattern
        // 3. Read selection; if editable and empty selection → SelectAll
        // 4. Fallback: clipboard session with Ctrl+C (selection first), then Ctrl+A+Ctrl+C
        throw FocusedTextIoException.AccessibilityDenied();
    }

    public Task ReplaceSelectionAsync(
        FocusedTextCapture capture,
        string text,
        CancellationToken cancellationToken = default)
    {
        if (!OperatingSystem.IsWindows())
            throw FocusedTextIoException.WriteFailed();

        // TODO(Windows): UIA write or Ctrl+V with clipboard session
        throw FocusedTextIoException.WriteFailed();
    }

    public void FinishClipboardSession(bool onlyIfUnchanged = false)
    {
        // TODO(Windows): restore user clipboard when safe
    }

    public bool IsFocusedTextEditable()
    {
        if (!OperatingSystem.IsWindows())
            return false;
        // TODO(Windows): UIA editable check with ancestor walk
        return false;
    }
}
