using Prism.Core.TextIO;

namespace Prism.Core.Policy;

public enum TranslationPresentationKind
{
    ReplaceInPlace,
    Popup,
}

public sealed record TranslationPresentation(TranslationPresentationKind Kind, bool SendAfter = false)
{
    public static TranslationPresentation ReplaceInPlace(bool sendAfter = false) =>
        new(TranslationPresentationKind.ReplaceInPlace, sendAfter);

    public static TranslationPresentation Popup() =>
        new(TranslationPresentationKind.Popup);
}

public enum TranslationTriggerKind
{
    HotkeyTranslateOnly,
    HotkeyTranslateAndSend,
    HotkeyPopup,
    EnterKey,
}

public sealed record TranslationTrigger(TranslationTriggerKind Kind, string? Chord = null)
{
    public string Title => Kind switch
    {
        TranslationTriggerKind.HotkeyTranslateOnly => $"hotkey «Translate» ({Chord})",
        TranslationTriggerKind.HotkeyTranslateAndSend => $"hotkey «Translate and send» ({Chord})",
        TranslationTriggerKind.HotkeyPopup => $"hotkey «Panel» ({Chord})",
        TranslationTriggerKind.EnterKey => "Enter key (translate-and-send mode)",
        _ => Kind.ToString(),
    };

    public string ExpectedOutcome => Kind switch
    {
        TranslationTriggerKind.HotkeyTranslateOnly => "translate and replace in field, without sending",
        TranslationTriggerKind.HotkeyTranslateAndSend or TranslationTriggerKind.EnterKey =>
            "translate, replace, and send (Enter)",
        TranslationTriggerKind.HotkeyPopup => "show result in floating panel",
        _ => "",
    };
}

public sealed record TranslationActionResolution(bool ShowPanel, bool CanReplace, bool SendAfter);

/// <summary>
/// Maps capture context + hotkey presentation to panel vs replace-in-place.
/// Language pair never affects this policy — only capture + presentation.
/// </summary>
public static class TranslationActionPolicy
{
    public static bool ShouldReplaceInField(bool preferReplaceInPlace, FocusedTextCapture capture) =>
        capture.IsEditable;

    public static TranslationActionResolution Resolve(
        TranslationPresentation presentation,
        FocusedTextCapture capture)
    {
        var preferReplaceInPlace = presentation.Kind == TranslationPresentationKind.ReplaceInPlace;
        var replaceInField = ShouldReplaceInField(preferReplaceInPlace, capture);

        return presentation.Kind switch
        {
            TranslationPresentationKind.ReplaceInPlace => new TranslationActionResolution(
                ShowPanel: !replaceInField,
                CanReplace: false,
                SendAfter: presentation.SendAfter),
            TranslationPresentationKind.Popup => new TranslationActionResolution(
                ShowPanel: true,
                CanReplace: replaceInField,
                SendAfter: false),
            _ => new TranslationActionResolution(true, false, false),
        };
    }
}
