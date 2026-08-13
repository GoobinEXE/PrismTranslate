import XCTest

@testable import Prism

final class GeminiParsingTests: XCTestCase {
    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    func testParsesFirstCandidateText() throws {
        let payload = data(#"""
        {"candidates":[{"content":{"parts":[{"text":"Hello, world!"}],"role":"model"}}]}
        """#)
        XCTAssertEqual(try GeminiProvider.parseGenerateContent(from: payload), "Hello, world!")
    }

    func testJoinsMultipleParts() throws {
        let payload = data(#"""
        {"candidates":[{"content":{"parts":[{"text":"Olá, "},{"text":"mundo!"}]}}]}
        """#)
        XCTAssertEqual(try GeminiProvider.parseGenerateContent(from: payload), "Olá, mundo!")
    }

    func testTrimsWhitespace() throws {
        let payload = data(#"""
        {"candidates":[{"content":{"parts":[{"text":"\n  Traduzido  \n"}]}}]}
        """#)
        XCTAssertEqual(try GeminiProvider.parseGenerateContent(from: payload), "Traduzido")
    }

    func testThrowsOnEmptyCandidates() {
        let payload = data(#"{"candidates":[]}"#)
        XCTAssertThrowsError(try GeminiProvider.parseGenerateContent(from: payload)) { error in
            guard case TranslationError.emptyResponse = error else {
                return XCTFail("Esperava TranslationError.emptyResponse, recebeu \(error)")
            }
        }
    }

    func testThrowsOnMissingText() {
        let payload = data(#"{"candidates":[{"content":{"parts":[{"text":null}]}}]}"#)
        XCTAssertThrowsError(try GeminiProvider.parseGenerateContent(from: payload))
    }

    func testThrowsOnMalformedJSON() {
        XCTAssertThrowsError(try GeminiProvider.parseGenerateContent(from: data("not json")))
    }
}
