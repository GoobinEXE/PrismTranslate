import AppKit
import ApplicationServices
import Foundation

enum FocusedTextIOError: LocalizedError, Equatable {
    case accessibilityDenied
    case noFocusedElement
    case noSelectionInReadOnly
    case emptyClipboard
    case writeFailed
    case readFallbackFailed
    case writeFallbackFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return String(
                localized:
                    "Accessibility permission required — open System Settings › Privacy › Accessibility"
            )
        case .noFocusedElement:
            return String(localized: "No focused text field")
        case .noSelectionInReadOnly:
            return String(localized: "Select the text to translate")
        case .emptyClipboard:
            return String(localized: "Couldn’t read the field text")
        case .writeFailed:
            return String(localized: "Couldn’t replace the text")
        case .readFallbackFailed:
            return String(
                localized:
                    "Failed to read the field (Accessibility and clipboard fallback both failed)")
        case .writeFallbackFailed:
            return String(
                localized:
                    "Failed to replace the text (Accessibility and clipboard fallback both failed)")
        }
    }
}

/// Snapshot of what was captured so replacement can re-select if needed.
struct FocusedTextCapture: Equatable {
    let text: String
    /// True when we selected the whole field (no prior user selection).
    let didSelectAll: Bool
    /// True when AX could not read the field and we borrowed the clipboard (⌘A/⌘C).
    /// Replace should paste via clipboard too — AX write is unreliable for those hosts (Mail WebArea, etc.).
    let usedClipboardForRead: Bool
    /// Whether the focused element looked editable at capture time.
    let isEditable: Bool
    /// Selection (or focused field) bounds in Cocoa screen coordinates, captured at read time.
    let selectionScreenRect: CGRect?

    init(
        text: String,
        didSelectAll: Bool,
        usedClipboardForRead: Bool = false,
        isEditable: Bool,
        selectionScreenRect: CGRect? = nil
    ) {
        self.text = text
        self.didSelectAll = didSelectAll
        self.usedClipboardForRead = usedClipboardForRead
        self.isEditable = isEditable
        self.selectionScreenRect = selectionScreenRect
    }

    /// Resumo em português para o log (sem jargão de AX).
    var logSummary: String {
        var parts: [String] = ["\(text.count) caracteres"]
        parts.append(isEditable ? "campo editável" : "texto só leitura")
        if didSelectAll {
            parts.append("campo inteiro (não havia seleção)")
        } else {
            parts.append("seleção do usuário")
        }
        parts.append(usedClipboardForRead ? "lido via clipboard (⌘C)" : "lido via Acessibilidade")
        return parts.joined(separator: ", ")
    }
}

/// Reads and replaces text in the focused UI element.
///
/// Pipeline (DeepL-like): ensure selection → read → translate (caller) → replace selection.
final class FocusedTextIO {

    /// Wraps synthetic keystrokes so the global event tap does not re-intercept them.
    var withInjection: ((() -> Void) -> Void)?

    /// User clipboard captured before a clipboard-based read. Held until write finishes or
    /// `finishPasteboardSession()` runs — never restored on a timer during translation
    /// (that raced with paste and could inject the user's old clipboard into the field).
    private var pendingUserPasteboard: PasteboardBackup?

    /// Roles that are always treated as editable text contexts.
    private static let editableTextRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
    ]

    /// True when the focused UI element looks like an editable text field/area.
    /// Used so Enter-mode interception does not steal Return outside text contexts,
    /// and so select-all / popup Replace run on WebKit compose (Mail) and similar hosts.
    static func isFocusedTextEditable() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let element = focusedElement() else { return false }
        // Walk a few ancestors: focus is sometimes on a non-text child inside the editor.
        return isElementOrAncestorEditable(element, maxDepth: 4)
    }

    /// Focused element or a near ancestor looks editable (text role, AXEditable, or settable AXValue).
    private static func isElementOrAncestorEditable(_ element: AXUIElement, maxDepth: Int) -> Bool {
        var current: AXUIElement? = element
        var depth = 0
        while let el = current, depth <= maxDepth {
            if elementLooksEditable(el) {
                return true
            }
            current = parentElement(of: el)
            depth += 1
        }
        return false
    }

    private static func elementLooksEditable(_ element: AXUIElement) -> Bool {
        if let role = roleString(of: element), editableTextRoles.contains(role) {
            return true
        }

        // WebKit/Mail contenteditable and many web editors expose AXEditable on AXWebArea.
        if boolAttribute(element, "AXEditable") == true {
            return true
        }

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            == .success,
            settable.boolValue
        {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success,
                valueRef is String
            {
                return true
            }
        }

        return false
    }

    private static func roleString(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
                == .success
        else {
            return nil
        }
        return roleRef as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success, let ref
        else {
            return nil
        }
        if let number = ref as? NSNumber {
            return number.boolValue
        }
        if CFGetTypeID(ref) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((ref as! CFBoolean))
        }
        return nil
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        var parentRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef)
                == .success,
            let parentRef
        else {
            return nil
        }
        return (parentRef as! AXUIElement)
    }

    /// Restores any borrowed user clipboard (e.g. translate failed after a clipboard read).
    /// When `onlyIfUnchanged` is true, skip restore if the user copied something else (panel Copiar).
    func finishPasteboardSession(onlyIfUnchanged: Bool = false) {
        let changeCount = onlyIfUnchanged ? NSPasteboard.general.changeCount : nil
        restorePendingUserPasteboard(after: 0.35, onlyIfChangeCount: changeCount)
    }

    /// Selects text if needed, then returns the selection for translation.
    /// Prefer existing selection; otherwise select-all (AX range or ⌘A) like DeepL on editable fields.
    /// When `preferReplaceInPlace` is true (⌃⌥T / ⌃⌥⏎ / Enter), infer editability for AX-opaque
    /// compose hosts so partial clipboard selections replace in-field instead of opening the panel.
    /// `allowSelectAllWhenEditable` is also true for ⌃⌥Y — select-all without compose replace heuristics.
    func selectAndReadFocusedText(
        preferReplaceInPlace: Bool = false,
        allowSelectAllWhenEditable: Bool = false
    ) async throws -> FocusedTextCapture {
        AppLog.debug(.textIO, "Leitura: tentando Acessibilidade no campo focado")
        let isEditable = Self.isFocusedTextEditable()
        let axError: FocusedTextIOError
        do {
            let capture = try selectAndReadViaAccessibility(isEditable: isEditable)
            AppLog.info(.textIO, "Leitura via Acessibilidade: \(capture.logSummary)")
            return capture
        } catch let error as FocusedTextIOError {
            if error == .accessibilityDenied { throw error }
            axError = error
            // Mail/WebKit AXWebArea often omits AXSelectedText even when the user highlighted
            // text — still try ⌘C on the existing selection before asking them to select.
            if error == .noSelectionInReadOnly {
                AppLog.warning(
                    .textIO, "Acessibilidade sem seleção — tentando copiar a seleção existente (⌘C)"
                )
            } else if error == .readFallbackFailed {
                // Editable host without AXValue — expected path into ⌘A+⌘C.
                AppLog.debug(
                    .textIO,
                    "Acessibilidade sem AXValue no campo editável — tentando clipboard (⌘A+⌘C)")
            } else {
                AppLog.warning(
                    .textIO,
                    "Acessibilidade falhou (\(error.errorDescription ?? "desconhecido")) — tentando clipboard"
                )
            }
        }

        // Clipboard fallback strategy:
        // 1) Always prefer ⌘C of the *existing* selection first (Discord chat highlight, PDF, etc.).
        // 2) ⌘A+⌘C when step 1 found no selection — editable AX host OR Electron (noFocusedElement).
        // Step 2 only runs after step 1 throws; never skips ⌘C when chat is still highlighted.
        let maySelectAllIfNoSelection =
            isEditable
            || (allowSelectAllWhenEditable
                && (axError == .readFallbackFailed || axError == .noFocusedElement))

        // Step 1: copy existing selection only (never ⌘A).
        do {
            let text = try await readViaClipboard(selectAllFirst: false)
            let treatAsEditable = Self.editableFlagForClipboardCapture(
                preferReplaceInPlace: preferReplaceInPlace,
                axError: axError,
                isEditable: isEditable
            )
            AppLog.info(
                .textIO,
                "Leitura via clipboard (seleção existente): \(text.count) caracteres, tratado como \(treatAsEditable ? "editável" : "só leitura")"
            )
            return FocusedTextCapture(
                text: text,
                didSelectAll: false,
                usedClipboardForRead: true,
                isEditable: treatAsEditable
            )
        } catch {
            AppLog.debug(.textIO, "Clipboard sem seleção existente — \(error.localizedDescription)")
        }

        // Step 2: no selection — select-all only for editable / AX-blind compose.
        guard maySelectAllIfNoSelection else {
            restorePendingUserPasteboard(after: 0.2)
            throw FocusedTextIOError.noSelectionInReadOnly
        }

        do {
            let text = try await readViaClipboard(selectAllFirst: true)
            let treatAsEditable = isEditable || axError == .readFallbackFailed || axError == .noFocusedElement
            AppLog.info(
                .textIO,
                "Leitura via clipboard (⌘A + ⌘C no campo inteiro): \(text.count) caracteres")
            return FocusedTextCapture(
                text: text,
                didSelectAll: true,
                usedClipboardForRead: true,
                isEditable: treatAsEditable
            )
        } catch {
            AppLog.error(.textIO, "Clipboard também falhou: \(error.localizedDescription)")
            restorePendingUserPasteboard(after: 0.2)
            if axError == .noFocusedElement, Self.focusedElement() == nil {
                throw FocusedTextIOError.readFallbackFailed
            }
            throw FocusedTextIOError.readFallbackFailed
        }
    }

    /// Replaces the previously captured selection with `text`.
    /// Re-selects the whole field when the capture used select-all (selection often drops during async translate).
    func replaceSelection(_ capture: FocusedTextCapture, with text: String) async throws {
        if capture.usedClipboardForRead {
            AppLog.debug(
                .textIO,
                "Substituição: pulando Acessibilidade (leitura foi via clipboard); colando direto")
        } else {
            AppLog.debug(
                .textIO,
                "Substituição: tentando Acessibilidade (campo inteiro=\(capture.didSelectAll))")
            do {
                try writeViaAccessibility(
                    text, preferSelectionOnly: true, previousText: capture.text)
                AppLog.info(.textIO, "Escrita via Acessibilidade confirmada")
                // AX path may still hold a pending borrow from a prior attempt; flush it.
                restorePendingUserPasteboard(after: 0.35)
                return
            } catch let error as FocusedTextIOError {
                if error == .accessibilityDenied {
                    throw error
                }
                AppLog.warning(
                    .textIO,
                    "Acessibilidade não escreveu (\(error.errorDescription ?? "?")) — tentando colar via clipboard (⌘V)"
                )
            }
        }

        // After a bogus AX "success", selection may still be intact — paste into it.
        // AX-blind clipboard reads copied an existing highlight: never ⌘A (Discord would
        // select the whole conversation). Only ⌘A when the capture itself was select-all.
        let hasSelection =
            Self.focusedElement().flatMap { selectedText(of: $0) }.map { !$0.isEmpty } ?? false
        let selectAllFirst: Bool
        if capture.didSelectAll {
            selectAllFirst = true
        } else if capture.usedClipboardForRead {
            selectAllFirst = false
        } else {
            selectAllFirst = !hasSelection
        }
        if selectAllFirst && !capture.didSelectAll {
            AppLog.debug(.textIO, "Clipboard: forçando ⌘A (a seleção sumiu depois da captura)")
        }

        do {
            try await writeViaClipboard(text, selectAllFirst: selectAllFirst)
            AppLog.info(.textIO, "Colagem via clipboard (⌘V) concluída")
        } catch {
            AppLog.error(.textIO, "Colagem via clipboard falhou: \(error.localizedDescription)")
            restorePendingUserPasteboard(after: 0.2)
            throw FocusedTextIOError.writeFallbackFailed
        }
    }

    /// Whether a clipboard read should be treated as an editable field for replace-in-place.
    /// Uses AX focus context at capture time — never mouse position.
    static func editableFlagForClipboardCapture(
        preferReplaceInPlace: Bool,
        axError: FocusedTextIOError,
        isEditable: Bool
    ) -> Bool {
        guard preferReplaceInPlace else { return isEditable }
        switch axError {
        case .noFocusedElement, .noSelectionInReadOnly:
            // Step 1: existing highlight while AX-blind — panel (chat/PDF safety).
            // Compose without selection uses step 2 (⌘A+⌘C) via maySelectAllIfNoSelection.
            return false
        case .readFallbackFailed:
            return true
        default:
            return isEditable
        }
    }

    // MARK: - Accessibility

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success, let focused = focusedRef
        else {
            return nil
        }
        return (focused as! AXUIElement)
    }

    private func selectAndReadViaAccessibility(isEditable: Bool) throws -> FocusedTextCapture {
        guard AXIsProcessTrusted() else {
            throw FocusedTextIOError.accessibilityDenied
        }
        guard let element = Self.focusedElement() else {
            AppLog.debug(.textIO, "📖 AX: nenhum elemento focado encontrado")
            throw FocusedTextIOError.noFocusedElement
        }

        // Log element role / AXEditable for diagnostics (Mail WebArea, Electron, etc.).
        let role = Self.roleString(of: element) ?? "desconhecido"
        let axEditable =
            Self.boolAttribute(element, "AXEditable").map { $0 ? "true" : "false" } ?? "nil"
        AppLog.debug(
            .textIO,
            "📖 AX elemento focado: role=\(role), AXEditable=\(axEditable), editable=\(isEditable)"
        )

        // 1) Existing selection — DeepL-style: translate only what the user highlighted.
        if let selected = selectedText(of: element) {
            AppLog.debug(.textIO, "📖 AX selectedText: \(selected.count) chars")
            if !selected.isEmpty {
                let rect =
                    Self.selectionScreenRect(of: element) ?? Self.elementScreenRect(of: element)
                return FocusedTextCapture(
                    text: selected,
                    didSelectAll: false,
                    isEditable: isEditable,
                    selectionScreenRect: rect
                )
            }
        } else {
            AppLog.debug(.textIO, "📖 AX selectedText: nil (atributo não suportado)")
        }

        // Read-only without a selection: never auto-select / grab whole document.
        guard isEditable else {
            AppLog.debug(.textIO, "📖 AX só leitura sem seleção — pedindo highlight ao usuário")
            throw FocusedTextIOError.noSelectionInReadOnly
        }

        // Editable but no AX selection — defer to clipboard (⌘C on existing highlight first, then ⌘A+⌘C).
        AppLog.debug(
            .textIO, "📖 AX editável sem seleção — deferindo para clipboard (⌘C antes de ⌘A)")
        throw FocusedTextIOError.readFallbackFailed
    }

    /// Cocoa-screen rect for the current selected text range, if AX exposes it.
    private static func selectionScreenRect(of element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &rangeRef
            ) == .success, let rangeRef
        else {
            return nil
        }

        var boundsRef: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        )
        guard status == .success, let boundsRef else { return nil }

        var axRect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &axRect), !axRect.isNull,
            !axRect.isEmpty
        else {
            return nil
        }
        return cocoaScreenRect(fromAX: axRect)
    }

    private static func elementScreenRect(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
                == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
                == .success,
            let posRef, let sizeRef
        else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else {
            return nil
        }
        let axRect = CGRect(origin: point, size: size)
        guard !axRect.isEmpty else { return nil }
        return cocoaScreenRect(fromAX: axRect)
    }

    /// AX uses top-left origin on the primary display; Cocoa uses bottom-left.
    private static func cocoaScreenRect(fromAX axRect: CGRect) -> CGRect {
        let primaryHeight =
            NSScreen.screens.first?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGRect(
            x: axRect.origin.x,
            y: primaryHeight - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    private func writeViaAccessibility(
        _ text: String,
        preferSelectionOnly: Bool,
        previousText: String
    ) throws {
        guard AXIsProcessTrusted() else {
            throw FocusedTextIOError.accessibilityDenied
        }
        guard let element = Self.focusedElement() else {
            throw FocusedTextIOError.noFocusedElement
        }

        if preferSelectionOnly {
            let hasSelection = selectedText(of: element).map { !$0.isEmpty } ?? false
            if hasSelection {
                let status = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextAttribute as CFString,
                    text as CFTypeRef
                )
                if status == .success {
                    if axWriteTookEffect(
                        on: element, expected: text, previous: previousText, viaSelection: true)
                    {
                        return
                    }
                    AppLog.warning(
                        .textIO,
                        "Acessibilidade disse sucesso mas o texto não mudou (falso positivo) — tentando outro caminho"
                    )
                    // Confirmed no-op: skip setValue — Chromium often mirrors AXValue after Set without
                    // updating the real editor, which would look like a verified setValue success.
                    if text != previousText,
                        selectedText(of: element) == previousText
                            || stringValue(of: element) == previousText
                    {
                        throw FocusedTextIOError.writeFailed
                    }
                } else {
                    AppLog.debug(.textIO, "✏️ AX setSelectedText falhou: status=\(status.rawValue)")
                }
            } else {
                AppLog.debug(.textIO, "✏️ AX sem seleção ativa para substituir")
            }
        }

        // Native AppKit fields often accept full value replacement.
        let setValue = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        if setValue == .success {
            if axWriteTookEffect(
                on: element, expected: text, previous: previousText, viaSelection: false)
            {
                return
            }
            AppLog.warning(
                .textIO,
                "Acessibilidade disse sucesso ao setValue mas o texto não mudou (falso positivo)")
        } else {
            AppLog.debug(.textIO, "✏️ AX setValue falhou: status=\(setValue.rawValue)")
        }

        throw FocusedTextIOError.writeFailed
    }

    /// Electron/Chromium apps (WhatsApp, etc.) often return AX `.success` without mutating the field.
    /// Re-read attributes so we don't skip the clipboard fallback on a no-op write.
    private func axWriteTookEffect(
        on element: AXUIElement,
        expected: String,
        previous: String,
        viaSelection: Bool
    ) -> Bool {
        if viaSelection {
            if let selected = selectedText(of: element), selected == expected {
                return true
            }
            // Whole-field replace may clear the selection while updating AXValue.
            if let value = stringValue(of: element), value == expected {
                return true
            }
            if expected != previous,
                selectedText(of: element) == previous || stringValue(of: element) == previous
            {
                AppLog.debug(.textIO, "✏️ AX verify: conteúdo ainda é o original")
            }
            return false
        }

        return stringValue(of: element) == expected
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success {
            return selectedRef as? String
        }

        // Mail/WebKit often omits AXSelectedText but still exposes range + stringForRange.
        var rangeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &rangeRef
            ) == .success, let rangeRef
        else {
            return nil
        }

        var stringRef: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeRef,
            &stringRef
        )
        guard status == .success else { return nil }
        return stringRef as? String
    }

    private func stringValue(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &valueRef
            ) == .success
        else {
            return nil
        }
        return valueRef as? String
    }

    /// Selects [0, length) via AXSelectedTextRange.
    @discardableResult
    private func selectAll(in element: AXUIElement, length: Int) -> Bool {
        guard length > 0 else { return false }
        var range = CFRange(location: 0, length: length)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return false }
        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        return status == .success
    }

    // MARK: - Clipboard fallback

    private func inject(_ work: () -> Void) {
        if let withInjection {
            withInjection(work)
        } else {
            work()
        }
    }

    /// Polls until the pasteboard changeCount advances and a non-empty string appears.
    private func waitForPasteboardString(
        pasteboard: NSPasteboard,
        afterChangeCount: Int,
        timeoutNanoseconds: UInt64
    ) async throws -> String {
        let pollNs: UInt64 = 8_000_000
        var waited: UInt64 = 0
        while waited < timeoutNanoseconds {
            if pasteboard.changeCount != afterChangeCount,
                let text = pasteboard.string(forType: .string),
                !text.isEmpty
            {
                return text
            }
            try await Task.sleep(nanoseconds: pollNs)
            waited += pollNs
        }
        if pasteboard.changeCount != afterChangeCount,
            let text = pasteboard.string(forType: .string),
            !text.isEmpty
        {
            return text
        }
        throw FocusedTextIOError.emptyClipboard
    }

    /// Brief settle after a synthetic key so the target app can process it.
    private func settleAfterKey(nanoseconds: UInt64 = 12_000_000) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func readViaClipboard(selectAllFirst: Bool) async throws -> String {
        let pasteboard = NSPasteboard.general
        // Hold the user's clipboard until write (or finishPasteboardSession) — do NOT
        // schedule a timed restore here; it raced with paste and could paste stale data.
        if pendingUserPasteboard == nil {
            pendingUserPasteboard = PasteboardBackup.capture(pasteboard)
        }

        // Clear so we do not confuse stale clipboard with a failed copy.
        pasteboard.clearContents()
        let changeCount = pasteboard.changeCount

        if selectAllFirst {
            inject { KeyboardSimulator.pressCommandKey("a") }
            try await settleAfterKey()
        }
        inject { KeyboardSimulator.pressCommandKey("c") }

        do {
            // Fast apps fill in <30ms; Electron/Chrome may need a few hundred.
            return try await waitForPasteboardString(
                pasteboard: pasteboard,
                afterChangeCount: changeCount,
                timeoutNanoseconds: 350_000_000
            )
        } catch {
            AppLog.warning(.textIO, "Clipboard ainda vazio depois de esperar a cópia — desistindo")
            throw FocusedTextIOError.emptyClipboard
        }
    }

    private func writeViaClipboard(_ text: String, selectAllFirst: Bool) async throws {
        let pasteboard = NSPasteboard.general
        // Prefer the pre-read user clipboard so we don't "restore" the copied draft.
        let backup = pendingUserPasteboard ?? PasteboardBackup.capture(pasteboard)
        pendingUserPasteboard = nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Re-select before paste: async translation often clears the selection.
        if selectAllFirst {
            inject { KeyboardSimulator.pressCommandKey("a") }
            try await settleAfterKey()
        }

        // Re-assert immediately before ⌘V so any concurrent pasteboard mutation cannot win.
        if pasteboard.string(forType: .string) != text {
            AppLog.warning(.textIO, "Clipboard mudou antes de colar — regravando a tradução")
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        let changeCountAtPaste = pasteboard.changeCount
        inject { KeyboardSimulator.pressCommandKey("v") }
        // Short settle so the paste lands before we restore the user's clipboard.
        try await settleAfterKey(nanoseconds: 40_000_000)

        backup.restore(after: 0.45, onlyIfChangeCount: changeCountAtPaste)
    }

    private func restorePendingUserPasteboard(
        after delay: TimeInterval, onlyIfChangeCount: Int? = nil
    ) {
        guard let backup = pendingUserPasteboard else { return }
        pendingUserPasteboard = nil
        AppLog.debug(.textIO, "📋 restaurando clipboard do usuário (pending session)")
        backup.restore(after: delay, onlyIfChangeCount: onlyIfChangeCount)
    }
}

private struct PasteboardBackup {
    let items: [[String: Data]]

    static func capture(_ pasteboard: NSPasteboard) -> PasteboardBackup {
        var archived: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            archived.append(dict)
        }
        return PasteboardBackup(items: archived)
    }

    /// Restores only if the pasteboard was not modified since `onlyIfChangeCount`.
    /// When `onlyIfChangeCount` is nil, always restores.
    func restore(after delay: TimeInterval, onlyIfChangeCount: Int? = nil) {
        let snapshot = items
        let expectedCount = onlyIfChangeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let pasteboard = NSPasteboard.general
            if let expectedCount, pasteboard.changeCount != expectedCount {
                // Another writer took ownership (or user copied something) — leave it alone.
                return
            }
            pasteboard.clearContents()
            for dict in snapshot {
                let item = NSPasteboardItem()
                for (type, data) in dict {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
                pasteboard.writeObjects([item])
            }
        }
    }
}
