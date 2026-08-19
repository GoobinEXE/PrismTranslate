import Foundation

/// Resolved UI action after translation: panel vs in-place replace.
struct TranslationActionResolution: Equatable {
    let showPanel: Bool
    let canReplace: Bool
    let sendAfter: Bool
}

/// Maps capture context + hotkey presentation to panel vs replace-in-place.
///
/// Invariants:
/// - Language pair (`usedOutgoingPair`) never affects this policy — only capture + presentation.
/// - Replace vs panel follows `capture.isEditable` (AX + clipboard axError context at capture time).
/// - No mouse/window-band heuristics — cursor position is unpredictable for the user.
/// - Confirmed read-only with `.replaceInPlace` → panel, Copiar only.
enum TranslationActionPolicy {

    /// True when the translation should be pasted into the focused field instead of the panel.
    static func shouldReplaceInField(
        preferReplaceInPlace: Bool,
        capture: FocusedTextCapture
    ) -> Bool {
        capture.isEditable
    }

    static func resolve(
        presentation: TranslationPresentation,
        capture: FocusedTextCapture
    ) -> TranslationActionResolution {
        let preferReplaceInPlace: Bool
        switch presentation {
        case .replaceInPlace:
            preferReplaceInPlace = true
        case .popup:
            preferReplaceInPlace = false
        }

        let replaceInField = shouldReplaceInField(
            preferReplaceInPlace: preferReplaceInPlace,
            capture: capture
        )

        switch presentation {
        case .replaceInPlace(let sendAfter):
            return TranslationActionResolution(
                showPanel: !replaceInField,
                canReplace: false,
                sendAfter: sendAfter
            )
        case .popup:
            return TranslationActionResolution(
                showPanel: true,
                canReplace: replaceInField,
                sendAfter: false
            )
        }
    }
}
