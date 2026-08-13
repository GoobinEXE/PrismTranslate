import XCTest

@testable import Prism

final class OpenAICompatibleParsingTests: XCTestCase {
    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    func testParsesFirstChoiceContent() throws {
        let payload = data(#"""
        {"choices": [{"message": {"role": "assistant", "content": "Hello, world!"}}]}
        """#)
        XCTAssertEqual(try OpenAICompatibleProvider.parseChatContent(from: payload), "Hello, world!")
    }

    func testTrimsWhitespaceAndNewlines() throws {
        let payload = data(#"""
        {"choices": [{"message": {"content": "\n  Olá, mundo!  \n"}}]}
        """#)
        XCTAssertEqual(try OpenAICompatibleProvider.parseChatContent(from: payload), "Olá, mundo!")
    }

    func testIgnoresExtraFieldsAndExtraChoices() throws {
        let payload = data(#"""
        {
          "id": "chatcmpl-123",
          "model": "local-model",
          "usage": {"total_tokens": 7},
          "choices": [
            {"index": 0, "finish_reason": "stop", "message": {"content": "primeiro"}},
            {"index": 1, "message": {"content": "segundo"}}
          ]
        }
        """#)
        XCTAssertEqual(try OpenAICompatibleProvider.parseChatContent(from: payload), "primeiro")
    }

    func testThrowsOnEmptyContent() {
        let payload = data(#"{"choices": [{"message": {"content": "   "}}]}"#)
        XCTAssertThrowsError(try OpenAICompatibleProvider.parseChatContent(from: payload)) { error in
            guard case TranslationError.emptyResponse = error else {
                return XCTFail("Esperava TranslationError.emptyResponse, recebeu \(error)")
            }
        }
    }

    func testThrowsOnNullContent() {
        let payload = data(#"{"choices": [{"message": {"content": null}}]}"#)
        XCTAssertThrowsError(try OpenAICompatibleProvider.parseChatContent(from: payload))
    }

    func testThrowsOnEmptyChoices() {
        let payload = data(#"{"choices": []}"#)
        XCTAssertThrowsError(try OpenAICompatibleProvider.parseChatContent(from: payload)) { error in
            guard case TranslationError.emptyResponse = error else {
                return XCTFail("Esperava TranslationError.emptyResponse, recebeu \(error)")
            }
        }
    }

    func testThrowsOnMalformedJSON() {
        let payload = data("not json at all")
        XCTAssertThrowsError(try OpenAICompatibleProvider.parseChatContent(from: payload))
    }
}
