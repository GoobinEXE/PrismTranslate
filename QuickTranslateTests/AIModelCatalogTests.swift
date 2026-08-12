import XCTest
@testable import QuickTranslate

final class AIModelCatalogTests: XCTestCase {
    func testPickBestPrefersFirstAvailablePreferredModel() {
        let available: Set<String> = [
            "llama-3.3-70b-versatile",
            "openai/gpt-oss-20b",
            "whisper-large-v3"
        ]
        XCTAssertEqual(
            AIModelCatalog.pickBestModel(for: .groq, available: available),
            "llama-3.3-70b-versatile"
        )
    }

    func testPickBestFallsBackToScoredFlashLite() {
        let available: Set<String> = [
            "gemini-2.5-pro",
            "gemini-3.5-flash-lite",
            "embed-text"
        ]
        XCTAssertEqual(
            AIModelCatalog.pickBestModel(for: .gemini, available: available),
            "gemini-3.5-flash-lite"
        )
    }

    func testKnownDeprecatedGemini25Flash() {
        XCTAssertTrue(AIModelCatalog.isKnownDeprecated(.gemini, model: "gemini-2.5-flash"))
        XCTAssertFalse(AIModelCatalog.isKnownDeprecated(.gemini, model: "gemini-flash-lite-latest"))
    }

    func testProviderDisplayNamesHaveNoParentheses() {
        for kind in ProviderKind.allCases {
            XCTAssertFalse(
                kind.displayName.contains("(") || kind.displayName.contains(")"),
                "\(kind.rawValue) ainda usa parênteses: \(kind.displayName)"
            )
            XCTAssertFalse(kind.symbolName.isEmpty)
            XCTAssertFalse(kind.badges.isEmpty)
        }
    }

    func testAIEnginesExposeBadgeIA() {
        for kind in [ProviderKind.groq, .gemini, .mistral, .deepSeek, .openRouter, .openAICompatible] {
            XCTAssertTrue(kind.badges.contains(.ai), "\(kind.rawValue) deveria ter badge IA")
        }
        XCTAssertFalse(ProviderKind.apple.badges.contains(.ai))
        XCTAssertFalse(ProviderKind.deepl.badges.contains(.ai))
    }
}
