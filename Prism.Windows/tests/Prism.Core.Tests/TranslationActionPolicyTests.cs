using Prism.Core.Policy;
using Prism.Core.TextIO;

namespace Prism.Core.Tests;

public class TranslationActionPolicyTests
{
    private static FocusedTextCapture Capture(
        bool isEditable,
        bool didSelectAll = false,
        bool usedClipboardForRead = false) =>
        new("hello", didSelectAll, usedClipboardForRead, isEditable);

    [Fact]
    public void TranslateOnly_ReadOnly_ShowsPanel()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.ReplaceInPlace(sendAfter: false),
            Capture(isEditable: false, usedClipboardForRead: true));

        Assert.True(result.ShowPanel);
        Assert.False(result.CanReplace);
        Assert.False(result.SendAfter);
    }

    [Fact]
    public void TranslateOnly_EditableField_ReplacesInPlace()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.ReplaceInPlace(sendAfter: false),
            Capture(isEditable: true));

        Assert.False(result.ShowPanel);
        Assert.False(result.CanReplace);
    }

    [Fact]
    public void TranslateOnly_ComposeClipboard_ReplacesInPlace()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.ReplaceInPlace(sendAfter: false),
            Capture(isEditable: true, usedClipboardForRead: true));

        Assert.False(result.ShowPanel);
        Assert.False(result.CanReplace);
    }

    [Fact]
    public void TranslateAndSend_SetsSendAfter()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.ReplaceInPlace(sendAfter: true),
            Capture(isEditable: true));

        Assert.False(result.ShowPanel);
        Assert.True(result.SendAfter);
    }

    [Fact]
    public void SelectAll_ReadOnly_ShowsPanel()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.ReplaceInPlace(sendAfter: false),
            Capture(isEditable: false, didSelectAll: true, usedClipboardForRead: true));

        Assert.True(result.ShowPanel);
    }

    [Fact]
    public void Popup_AlwaysShowsPanel()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.Popup(),
            Capture(isEditable: false));

        Assert.True(result.ShowPanel);
        Assert.False(result.CanReplace);
        Assert.False(result.SendAfter);
    }

    [Fact]
    public void Popup_CanReplace_WhenEditable()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.Popup(),
            Capture(isEditable: true));

        Assert.True(result.ShowPanel);
        Assert.True(result.CanReplace);
    }

    [Fact]
    public void Popup_ReadOnly_StillCopyOnly()
    {
        var result = TranslationActionPolicy.Resolve(
            TranslationPresentation.Popup(),
            Capture(isEditable: false, usedClipboardForRead: true));

        Assert.True(result.ShowPanel);
        Assert.False(result.CanReplace);
    }

    [Fact]
    public void ShouldReplaceInField_FollowsCaptureEditableOnly()
    {
        Assert.False(TranslationActionPolicy.ShouldReplaceInField(
            preferReplaceInPlace: true,
            Capture(isEditable: false, usedClipboardForRead: true)));
        Assert.True(TranslationActionPolicy.ShouldReplaceInField(
            preferReplaceInPlace: true,
            Capture(isEditable: true)));
    }

    [Fact]
    public void ReadFallbackFailed_IsEditableForClipboard()
    {
        Assert.True(FocusedTextCaptureRules.EditableFlagForClipboardCapture(
            preferReplaceInPlace: true,
            FocusedTextIoErrorKind.ReadFallbackFailed,
            isEditable: true));
    }

    [Fact]
    public void NoFocusedElement_Clipboard_IsNeverEditable()
    {
        Assert.False(FocusedTextCaptureRules.EditableFlagForClipboardCapture(
            preferReplaceInPlace: true,
            FocusedTextIoErrorKind.NoFocusedElement,
            isEditable: false));
    }

    [Fact]
    public void NoSelectionInReadOnly_Clipboard_IsNeverEditable()
    {
        Assert.False(FocusedTextCaptureRules.EditableFlagForClipboardCapture(
            preferReplaceInPlace: true,
            FocusedTextIoErrorKind.NoSelectionInReadOnly,
            isEditable: false));
    }
}
