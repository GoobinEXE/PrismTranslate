namespace Prism.Core.TextIO;

public sealed record FocusedTextCapture(
    string Text,
    bool DidSelectAll,
    bool UsedClipboardForRead,
    bool IsEditable,
    RectangleF? SelectionScreenRect = null)
{
    public string LogSummary
    {
        get
        {
            var parts = new List<string>
            {
                $"{Text.Length} characters",
                IsEditable ? "editable field" : "read-only text",
                DidSelectAll ? "whole field (no prior selection)" : "user selection",
                UsedClipboardForRead ? "read via clipboard" : "read via UI Automation",
            };
            return string.Join(", ", parts);
        }
    }
}

public readonly record struct RectangleF(float X, float Y, float Width, float Height);

public enum FocusedTextIoErrorKind
{
    AccessibilityDenied,
    NoFocusedElement,
    NoSelectionInReadOnly,
    EmptyClipboard,
    WriteFailed,
    ReadFallbackFailed,
    WriteFallbackFailed,
}

public sealed class FocusedTextIoException : Exception
{
    public FocusedTextIoErrorKind ErrorKind { get; }

    public FocusedTextIoException(FocusedTextIoErrorKind kind, string message)
        : base(message)
    {
        ErrorKind = kind;
    }

    public static FocusedTextIoException AccessibilityDenied() =>
        new(FocusedTextIoErrorKind.AccessibilityDenied,
            "Accessibility permission required — open Windows Settings › Privacy › Accessibility");

    public static FocusedTextIoException NoFocusedElement() =>
        new(FocusedTextIoErrorKind.NoFocusedElement, "No focused text field");

    public static FocusedTextIoException NoSelectionInReadOnly() =>
        new(FocusedTextIoErrorKind.NoSelectionInReadOnly, "Select the text to translate");

    public static FocusedTextIoException EmptyClipboard() =>
        new(FocusedTextIoErrorKind.EmptyClipboard, "Couldn’t read the field text");

    public static FocusedTextIoException WriteFailed() =>
        new(FocusedTextIoErrorKind.WriteFailed, "Couldn’t replace the text");

    public static FocusedTextIoException ReadFallbackFailed() =>
        new(FocusedTextIoErrorKind.ReadFallbackFailed,
            "Failed to read the field (UI Automation and clipboard fallback both failed)");

    public static FocusedTextIoException WriteFallbackFailed() =>
        new(FocusedTextIoErrorKind.WriteFallbackFailed,
            "Failed to replace the text (UI Automation and clipboard fallback both failed)");
}

/// <summary>
/// Mirrors macOS FocusedTextIO.editableFlagForClipboardCapture.
/// </summary>
public static class FocusedTextCaptureRules
{
    public static bool EditableFlagForClipboardCapture(
        bool preferReplaceInPlace,
        FocusedTextIoErrorKind axError,
        bool isEditable)
    {
        return axError switch
        {
            FocusedTextIoErrorKind.NoFocusedElement => false,
            FocusedTextIoErrorKind.NoSelectionInReadOnly => false,
            FocusedTextIoErrorKind.ReadFallbackFailed => preferReplaceInPlace && isEditable,
            _ => isEditable,
        };
    }
}
