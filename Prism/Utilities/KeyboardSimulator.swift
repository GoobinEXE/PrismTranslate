import AppKit
import Carbon.HIToolbox
import Foundation

enum KeyboardSimulator {
    static func pressReturn() {
        postKey(keyCode: CGKeyCode(kVK_Return), flags: [])
    }

    static func pressCommandKey(_ character: String) {
        guard let keyCode = keyCode(for: character) else { return }
        postKey(keyCode: keyCode, flags: .maskCommand)
    }

    static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func keyCode(for character: String) -> CGKeyCode? {
        switch character.lowercased() {
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "t": return CGKeyCode(kVK_ANSI_T)
        default: return nil
        }
    }
}
