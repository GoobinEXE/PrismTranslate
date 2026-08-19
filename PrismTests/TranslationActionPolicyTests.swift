import CoreGraphics
import XCTest

@testable import Prism

final class TranslationActionPolicyTests: XCTestCase {

    private func capture(
        isEditable: Bool,
        didSelectAll: Bool = false,
        usedClipboardForRead: Bool = false
    ) -> FocusedTextCapture {
        FocusedTextCapture(
            text: "hello",
            didSelectAll: didSelectAll,
            usedClipboardForRead: usedClipboardForRead,
            isEditable: isEditable
        )
    }

    // MARK: - ⌃⌥T (.replaceInPlace)

    func testTranslateOnlyReadOnlyShowsPanel() {
        let result = TranslationActionPolicy.resolve(
            presentation: .replaceInPlace(sendAfter: false),
            capture: capture(isEditable: false, usedClipboardForRead: true)
        )
        XCTAssertTrue(result.showPanel)
        XCTAssertFalse(result.canReplace)
        XCTAssertFalse(result.sendAfter)
    }

    func testTranslateOnlyEditableFieldReplacesInPlace() {
        let result = TranslationActionPolicy.resolve(
            presentation: .replaceInPlace(sendAfter: false),
            capture: capture(isEditable: true)
        )
        XCTAssertFalse(result.showPanel)
        XCTAssertFalse(result.canReplace)
    }

    func testTranslateOnlyComposeClipboardReplacesInPlace() {
        // Simulates readFallbackFailed clipboard path (Discord compose with AX focus).
        let result = TranslationActionPolicy.resolve(
            presentation: .replaceInPlace(sendAfter: false),
            capture: capture(isEditable: true, usedClipboardForRead: true)
        )
        XCTAssertFalse(result.showPanel)
        XCTAssertFalse(result.canReplace)
    }

    func testTranslateAndSendSetsSendAfter() {
        let result = TranslationActionPolicy.resolve(
            presentation: .replaceInPlace(sendAfter: true),
            capture: capture(isEditable: true)
        )
        XCTAssertFalse(result.showPanel)
        XCTAssertTrue(result.sendAfter)
    }

    func testSelectAllReadOnlyShowsPanel() {
        let result = TranslationActionPolicy.resolve(
            presentation: .replaceInPlace(sendAfter: false),
            capture: capture(isEditable: false, didSelectAll: true, usedClipboardForRead: true)
        )
        XCTAssertTrue(result.showPanel)
    }

    // MARK: - ⌃⌥Y (.popup)

    func testPopupAlwaysShowsPanel() {
        let result = TranslationActionPolicy.resolve(
            presentation: .popup,
            capture: capture(isEditable: false)
        )
        XCTAssertTrue(result.showPanel)
        XCTAssertFalse(result.canReplace)
        XCTAssertFalse(result.sendAfter)
    }

    func testPopupCanReplaceWhenEditable() {
        let result = TranslationActionPolicy.resolve(
            presentation: .popup,
            capture: capture(isEditable: true)
        )
        XCTAssertTrue(result.showPanel)
        XCTAssertTrue(result.canReplace)
    }

    func testPopupReadOnlyStillCopyOnly() {
        let result = TranslationActionPolicy.resolve(
            presentation: .popup,
            capture: capture(isEditable: false, usedClipboardForRead: true)
        )
        XCTAssertTrue(result.showPanel)
        XCTAssertFalse(result.canReplace)
    }

    // MARK: - shouldReplaceInField

    func testShouldReplaceInFieldFollowsCaptureEditableOnly() {
        XCTAssertFalse(
            TranslationActionPolicy.shouldReplaceInField(
                preferReplaceInPlace: true,
                capture: capture(isEditable: false, usedClipboardForRead: true)
            )
        )
        XCTAssertTrue(
            TranslationActionPolicy.shouldReplaceInField(
                preferReplaceInPlace: true,
                capture: capture(isEditable: true)
            )
        )
    }

    // MARK: - Clipboard editable flag (AX context, no mouse)

    func testReadFallbackFailedIsEditableForClipboard() {
        XCTAssertTrue(
            FocusedTextIO.editableFlagForClipboardCapture(
                preferReplaceInPlace: true,
                axError: .readFallbackFailed,
                isEditable: true
            )
        )
    }

    func testNoFocusedElementClipboardIsNeverEditable() {
        XCTAssertFalse(
            FocusedTextIO.editableFlagForClipboardCapture(
                preferReplaceInPlace: true,
                axError: .noFocusedElement,
                isEditable: false
            )
        )
    }

    func testNoSelectionInReadOnlyClipboardIsNeverEditable() {
        XCTAssertFalse(
            FocusedTextIO.editableFlagForClipboardCapture(
                preferReplaceInPlace: true,
                axError: .noSelectionInReadOnly,
                isEditable: false
            )
        )
    }
}
