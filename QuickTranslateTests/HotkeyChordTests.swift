import Carbon.HIToolbox
import CoreGraphics
import XCTest

@testable import QuickTranslate

final class HotkeyChordTests: XCTestCase {
    // MARK: Defaults

    func testTranslateOnlyDefaultIsControlOptionT() {
        let chord = HotkeyChord.translateOnlyDefault
        XCTAssertEqual(chord.keyCode, UInt16(kVK_ANSI_T))
        XCTAssertEqual(chord.modifiers, [.control, .option])
        XCTAssertFalse(chord.isReturnKey)
    }

    func testTranslateAndSendDefaultIsControlOptionReturn() {
        let chord = HotkeyChord.translateAndSendDefault
        XCTAssertEqual(chord.keyCode, UInt16(kVK_Return))
        XCTAssertEqual(chord.modifiers, [.control, .option])
        XCTAssertTrue(chord.isReturnKey)
    }

    // MARK: Matching

    func testMatchesExactKeyAndModifiers() {
        let chord = HotkeyChord.translateOnlyDefault
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        XCTAssertTrue(chord.matches(keyCode: Int64(kVK_ANSI_T), flags: flags))
    }

    func testDoesNotMatchDifferentKey() {
        let chord = HotkeyChord.translateOnlyDefault
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        XCTAssertFalse(chord.matches(keyCode: Int64(kVK_ANSI_S), flags: flags))
    }

    func testDoesNotMatchWithExtraModifier() {
        let chord = HotkeyChord.translateOnlyDefault
        let flags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
        XCTAssertFalse(chord.matches(keyCode: Int64(kVK_ANSI_T), flags: flags))
    }

    func testDoesNotMatchWithMissingModifier() {
        let chord = HotkeyChord.translateOnlyDefault
        XCTAssertFalse(chord.matches(keyCode: Int64(kVK_ANSI_T), flags: [.maskControl]))
    }

    func testReturnChordAlsoMatchesKeypadEnter() {
        let chord = HotkeyChord.translateAndSendDefault
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        XCTAssertTrue(chord.matches(keyCode: Int64(kVK_Return), flags: flags))
        XCTAssertTrue(chord.matches(keyCode: Int64(kVK_ANSI_KeypadEnter), flags: flags))
    }

    // MARK: Creation from events

    func testFromKeyCodeRequiresAtLeastOneModifier() {
        XCTAssertNil(HotkeyChord.from(keyCode: UInt16(kVK_ANSI_T), flags: []))
    }

    func testFromKeyCodeIgnoresModifierOnlyKeys() {
        let flags: CGEventFlags = [.maskControl]
        XCTAssertNil(HotkeyChord.from(keyCode: UInt16(kVK_Control), flags: flags))
        XCTAssertNil(HotkeyChord.from(keyCode: UInt16(kVK_Shift), flags: flags))
        XCTAssertNil(HotkeyChord.from(keyCode: UInt16(kVK_Command), flags: flags))
        XCTAssertNil(HotkeyChord.from(keyCode: UInt16(kVK_CapsLock), flags: flags))
    }

    func testFromKeyCodeBuildsChord() {
        let chord = HotkeyChord.from(
            keyCode: UInt16(kVK_ANSI_G),
            flags: [.maskCommand, .maskShift]
        )
        XCTAssertEqual(chord, HotkeyChord(keyCode: UInt16(kVK_ANSI_G), modifiers: [.command, .shift]))
    }

    // MARK: Validity and display

    func testIsValidRequiresModifiers() {
        XCTAssertFalse(HotkeyChord(keyCode: UInt16(kVK_ANSI_T), modifiers: []).isValid)
        XCTAssertTrue(HotkeyChord.translateOnlyDefault.isValid)
    }

    func testDisplayStringForDefaults() {
        XCTAssertEqual(HotkeyChord.translateOnlyDefault.displayString, "⌃⌥T")
        XCTAssertEqual(HotkeyChord.translateAndSendDefault.displayString, "⌃⌥⏎")
    }

    func testDisplayStringModifierOrder() {
        let chord = HotkeyChord(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: [.command, .shift, .option, .control]
        )
        XCTAssertEqual(chord.displayString, "⌃⌥⇧⌘A")
    }

    // MARK: Modifiers round-trip

    func testModifiersRoundTripThroughCGEventFlags() {
        let all: HotkeyChord.Modifiers = [.command, .shift, .option, .control]
        XCTAssertEqual(HotkeyChord.Modifiers(flags: all.cgEventFlags), all)

        let some: HotkeyChord.Modifiers = [.control, .option]
        XCTAssertEqual(HotkeyChord.Modifiers(flags: some.cgEventFlags), some)
    }

    func testModifiersMatchesIgnoresNonModifierFlags() {
        // CGEvents carry extra flags (e.g. .maskNonCoalesced); only ⌘⇧⌥⌃ should count.
        var flags: CGEventFlags = [.maskControl, .maskAlternate]
        flags.insert(.maskNonCoalesced)
        XCTAssertTrue(HotkeyChord.Modifiers.preferred.matches(flags))
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let original = HotkeyChord.translateAndSendDefault
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyChord.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
