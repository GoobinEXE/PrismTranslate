import AppKit
import Carbon.HIToolbox
import Foundation

/// A keyboard shortcut: one key + modifier flags (⌘⇧⌥⌃).
struct HotkeyChord: Equatable, Hashable, Codable {
    var keyCode: UInt16
    var modifiers: Modifiers

    struct Modifiers: OptionSet, Equatable, Hashable, Codable {
        let rawValue: UInt8

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)

        /// Defaults prefer Control+Option — rarely claimed by apps or the system.
        static let preferred: Modifiers = [.control, .option]
    }

    // MARK: Defaults

    /// ⌃⌥T — translate and replace (do not send).
    static let translateOnlyDefault = HotkeyChord(
        keyCode: UInt16(kVK_ANSI_T),
        modifiers: .preferred
    )

    /// ⌃⌥⏎ — translate, replace, and send.
    static let translateAndSendDefault = HotkeyChord(
        keyCode: UInt16(kVK_Return),
        modifiers: .preferred
    )

    // MARK: Matching

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let keyMatches: Bool
        if isReturnKey {
            keyMatches = keyCode == Int64(kVK_Return) || keyCode == Int64(kVK_ANSI_KeypadEnter)
        } else {
            keyMatches = keyCode == Int64(self.keyCode)
        }
        guard keyMatches else { return false }
        return modifiers.matches(flags)
    }

    /// True when this chord uses Return/Enter (relevant for “Enter traduz e envia”).
    var isReturnKey: Bool {
        keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter)
    }

    // MARK: Display

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    var isValid: Bool {
        !modifiers.isEmpty
    }

    // MARK: From events

    static func from(keyCode: UInt16, flags: CGEventFlags) -> HotkeyChord? {
        let mods = Modifiers(flags: flags)
        guard !mods.isEmpty else { return nil }
        // Ignore modifier-only key presses (left/right cmd, etc.).
        let modifierKeyCodes: Set<UInt16> = [
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_Function),
            UInt16(kVK_CapsLock),
        ]
        guard !modifierKeyCodes.contains(keyCode) else { return nil }
        return HotkeyChord(keyCode: keyCode, modifiers: mods)
    }

    static func from(nsEvent: NSEvent) -> HotkeyChord? {
        var flags: CGEventFlags = []
        let mods = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.shift) { flags.insert(.maskShift) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        return from(keyCode: UInt16(nsEvent.keyCode), flags: flags)
    }
}

// MARK: - Modifiers helpers

extension HotkeyChord.Modifiers {
    init(flags: CGEventFlags) {
        var value: UInt8 = 0
        if flags.contains(.maskCommand) { value |= Self.command.rawValue }
        if flags.contains(.maskShift) { value |= Self.shift.rawValue }
        if flags.contains(.maskAlternate) { value |= Self.option.rawValue }
        if flags.contains(.maskControl) { value |= Self.control.rawValue }
        self.init(rawValue: value)
    }

    func matches(_ flags: CGEventFlags) -> Bool {
        let present = HotkeyChord.Modifiers(flags: flags)
        return present == self
    }

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}

// MARK: - Key names

private extension HotkeyChord {
    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: return "⏎"
        case kVK_Space: return "Space"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        default:
            return "Key\(keyCode)"
        }
    }
}
