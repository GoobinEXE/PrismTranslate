import XCTest

@testable import Prism

@MainActor
final class TranslationEngineCacheTests: XCTestCase {
    private var engine: TranslationEngine!

    override func setUp() {
        super.setUp()
        var settings = AppSettings()
        settings.cacheTranslations = true
        settings.providerKind = .apple
        engine = TranslationEngine(settings: settings, appleBridge: AppleTranslationBridge())
    }

    func testDoesNotCacheTextLongerThan512Characters() {
        let longText = String(repeating: "a", count: 513)
        engine.testingSeedCache(
            text: longText,
            outcome: TranslationOutcome(text: "cached")
        )
        XCTAssertEqual(engine.testingCacheCount, 0)
    }

    func testCachesTextWithin512Characters() {
        let text = String(repeating: "a", count: 512)
        engine.testingSeedCache(
            text: text,
            outcome: TranslationOutcome(text: "cached")
        )
        XCTAssertEqual(engine.testingCacheCount, 1)
    }

    func testClearCacheOnBackgroundRemovesEntries() {
        engine.testingSeedCache(
            text: "hello",
            outcome: TranslationOutcome(text: "olá")
        )
        XCTAssertEqual(engine.testingCacheCount, 1)
        engine.clearCacheOnBackground()
        XCTAssertEqual(engine.testingCacheCount, 0)
    }

    func testCacheDisabledViaSettings() {
        var settings = AppSettings()
        settings.cacheTranslations = false
        engine.updateSettings(settings)
        engine.testingSeedCache(
            text: "hello",
            outcome: TranslationOutcome(text: "olá")
        )
        XCTAssertEqual(engine.testingCacheCount, 0)
    }
}
