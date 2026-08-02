import AppKit
import ApplicationServices
import Foundation
import os

enum FocusedTextIOError: LocalizedError, Equatable {
    case accessibilityDenied
    case noFocusedElement
    case emptyClipboard
    case writeFailed
    case readFallbackFailed
    case writeFallbackFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Permissão de Acessibilidade necessária — abra Ajustes do Sistema › Privacidade › Acessibilidade"
        case .noFocusedElement:
            return "Nenhum campo de texto focado"
        case .emptyClipboard:
            return "Não foi possível ler o texto do campo"
        case .writeFailed:
            return "Não foi possível substituir o texto"
        case .readFallbackFailed:
            return "Falha ao ler o campo (Acessibilidade e fallback de clipboard falharam)"
        case .writeFallbackFailed:
            return "Falha ao substituir o texto (Acessibilidade e fallback de clipboard falharam)"
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

    init(text: String, didSelectAll: Bool, usedClipboardForRead: Bool = false) {
        self.text = text
        self.didSelectAll = didSelectAll
        self.usedClipboardForRead = usedClipboardForRead
    }
}

/// Reads and replaces text in the focused UI element.
///
/// Pipeline (DeepL-like): ensure selection → read → translate (caller) → replace selection.
final class FocusedTextIO {
    private static let logger = Logger(subsystem: "com.quicktranslate", category: "TextIO")

    /// Wraps synthetic keystrokes so the global event tap does not re-intercept them.
    var withInjection: ((() -> Void) -> Void)?

    /// User clipboard captured before a clipboard-based read. Held until write finishes or
    /// `finishPasteboardSession()` runs — never restored on a timer during translation
    /// (that raced with paste and could inject the user's old clipboard into the field).
    private var pendingUserPasteboard: PasteboardBackup?

    /// True when the focused UI element looks like an editable text field/area.
    /// Used so Enter-mode interception does not steal Return outside text contexts.
    static func isFocusedTextEditable() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let element = focusedElement() else { return false }

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            let textRoles: Set<String> = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                kAXComboBoxRole as String,
                "AXSearchField"
            ]
            if textRoles.contains(role) {
                return true
            }
        }

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               valueRef is String {
                return true
            }
        }

        return false
    }

    /// Restores any borrowed user clipboard (e.g. translate failed after a clipboard read).
    func finishPasteboardSession() {
        restorePendingUserPasteboard(after: 0.35)
    }

    /// Selects text if needed, then returns the selection for translation.
    /// Prefer existing selection; otherwise select-all (AX range or ⌘A) like DeepL on editable fields.
    func selectAndReadFocusedText() async throws -> FocusedTextCapture {
        Self.logger.debug("📖 selectAndReadFocusedText — tentando via Accessibility")
        let axError: FocusedTextIOError
        do {
            let capture = try selectAndReadViaAccessibility()
            Self.logger.info("📖 leitura AX OK: \(capture.text.count) chars, didSelectAll=\(capture.didSelectAll)")
            return capture
        } catch let error as FocusedTextIOError {
            if error == .accessibilityDenied { throw error }
            axError = error
            Self.logger.warning("📖 AX falhou: \(error.errorDescription ?? "desconhecido", privacy: .public) — tentando clipboard fallback")
        }

        do {
            let text = try await readViaClipboard(selectAllFirst: true)
            Self.logger.info("📖 clipboard fallback OK: \(text.count) chars")
            return FocusedTextCapture(text: text, didSelectAll: true, usedClipboardForRead: true)
        } catch {
            Self.logger.error("📖 clipboard fallback falhou: \(error.localizedDescription, privacy: .public)")
            // Read failed — give the user clipboard back immediately.
            restorePendingUserPasteboard(after: 0.2)
            if axError == .noFocusedElement { throw axError }
            throw FocusedTextIOError.readFallbackFailed
        }
    }

    /// Replaces the previously captured selection with `text`.
    /// Re-selects the whole field when the capture used select-all (selection often drops during async translate).
    func replaceSelection(_ capture: FocusedTextCapture, with text: String) async throws {
        if capture.usedClipboardForRead {
            Self.logger.debug("✏️ replaceSelection — pulando AX (leitura foi via clipboard); paste direto")
        } else {
            Self.logger.debug("✏️ replaceSelection — tentando via Accessibility (didSelectAll=\(capture.didSelectAll))")
            do {
                try writeViaAccessibility(text, preferSelectionOnly: true, previousText: capture.text)
                Self.logger.info("✏️ escrita AX OK (verificada)")
                // AX path may still hold a pending borrow from a prior attempt; flush it.
                restorePendingUserPasteboard(after: 0.35)
                return
            } catch let error as FocusedTextIOError {
                if error == .accessibilityDenied {
                    throw error
                }
                Self.logger.warning("✏️ AX escrita falhou (\(error.errorDescription ?? "?", privacy: .public)) — tentando clipboard paste")
            }
        }

        // After a bogus AX "success", selection may still be intact — paste into it.
        // If selection is gone, force ⌘A even when the capture was a partial highlight.
        let hasSelection = Self.focusedElement().flatMap { selectedText(of: $0) }.map { !$0.isEmpty } ?? false
        let selectAllFirst = capture.didSelectAll || capture.usedClipboardForRead || !hasSelection
        if selectAllFirst && !capture.didSelectAll && !capture.usedClipboardForRead {
            Self.logger.debug("✏️ clipboard: forçando selectAll (seleção ausente após AX)")
        }

        do {
            try await writeViaClipboard(text, selectAllFirst: selectAllFirst)
            Self.logger.info("✏️ clipboard paste OK")
        } catch {
            Self.logger.error("✏️ clipboard paste falhou: \(error.localizedDescription, privacy: .public)")
            restorePendingUserPasteboard(after: 0.2)
            throw FocusedTextIOError.writeFallbackFailed
        }
    }

    // MARK: - Accessibility

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focused = focusedRef else {
            return nil
        }
        return (focused as! AXUIElement)
    }

    private func selectAndReadViaAccessibility() throws -> FocusedTextCapture {
        guard AXIsProcessTrusted() else {
            throw FocusedTextIOError.accessibilityDenied
        }
        guard let element = Self.focusedElement() else {
            Self.logger.debug("📖 AX: nenhum elemento focado encontrado")
            throw FocusedTextIOError.noFocusedElement
        }

        // Log element role for diagnostics.
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            Self.logger.debug("📖 AX elemento focado: role=\(role, privacy: .public)")
        } else {
            Self.logger.debug("📖 AX elemento focado: role desconhecido")
        }

        // 1) Existing selection — DeepL-style: translate only what the user highlighted.
        if let selected = selectedText(of: element) {
            Self.logger.debug("📖 AX selectedText: \(selected.count) chars")
            if !selected.isEmpty {
                return FocusedTextCapture(text: selected, didSelectAll: false)
            }
        } else {
            Self.logger.debug("📖 AX selectedText: nil (atributo não suportado)")
        }

        // 2) No selection — auto-select entire field contents.
        if let value = stringValue(of: element) {
            Self.logger.debug("📖 AX stringValue: \(value.count) chars")
            guard !value.isEmpty else {
                Self.logger.debug("📖 AX stringValue vazio — nenhum texto para traduzir")
                throw FocusedTextIOError.noFocusedElement
            }
            // Best-effort AX select-all. Electron often ignores the range; replace still does ⌘A+⌘V.
            let selectResult = selectAll(in: element, length: value.utf16.count)
            Self.logger.debug("📖 AX selectAll: \(selectResult ? "OK" : "falhou")")
            return FocusedTextCapture(text: value, didSelectAll: true)
        }

        Self.logger.debug("📖 AX stringValue: nil (atributo não suportado)")
        throw FocusedTextIOError.noFocusedElement
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
                    if axWriteTookEffect(on: element, expected: text, previous: previousText, viaSelection: true) {
                        return
                    }
                    Self.logger.warning("✏️ AX setSelectedText retornou success mas o texto não mudou (falso positivo)")
                    // Confirmed no-op: skip setValue — Chromium often mirrors AXValue after Set without
                    // updating the real editor, which would look like a verified setValue success.
                    if text != previousText,
                       selectedText(of: element) == previousText || stringValue(of: element) == previousText {
                        throw FocusedTextIOError.writeFailed
                    }
                } else {
                    Self.logger.debug("✏️ AX setSelectedText falhou: status=\(status.rawValue)")
                }
            } else {
                Self.logger.debug("✏️ AX sem seleção ativa para substituir")
            }
        }

        // Native AppKit fields often accept full value replacement.
        let setValue = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        if setValue == .success {
            if axWriteTookEffect(on: element, expected: text, previous: previousText, viaSelection: false) {
                return
            }
            Self.logger.warning("✏️ AX setValue retornou success mas o texto não mudou (falso positivo)")
        } else {
            Self.logger.debug("✏️ AX setValue falhou: status=\(setValue.rawValue)")
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
               selectedText(of: element) == previous || stringValue(of: element) == previous {
                Self.logger.debug("✏️ AX verify: conteúdo ainda é o original")
            }
            return false
        }

        return stringValue(of: element) == expected
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success else {
            return nil
        }
        return selectedRef as? String
    }

    private func stringValue(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success else {
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
               !text.isEmpty {
                return text
            }
            try await Task.sleep(nanoseconds: pollNs)
            waited += pollNs
        }
        if pasteboard.changeCount != afterChangeCount,
           let text = pasteboard.string(forType: .string),
           !text.isEmpty {
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
            Self.logger.warning("📋 clipboard continua vazio após poll — desistindo")
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
            Self.logger.warning("📋 clipboard divergiu antes do paste — regravando tradução")
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        let changeCountAtPaste = pasteboard.changeCount
        inject { KeyboardSimulator.pressCommandKey("v") }
        // Short settle so the paste lands before we restore the user's clipboard.
        try await settleAfterKey(nanoseconds: 40_000_000)

        backup.restore(after: 0.45, onlyIfChangeCount: changeCountAtPaste)
    }

    private func restorePendingUserPasteboard(after delay: TimeInterval) {
        guard let backup = pendingUserPasteboard else { return }
        pendingUserPasteboard = nil
        Self.logger.debug("📋 restaurando clipboard do usuário (pending session)")
        backup.restore(after: delay)
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
