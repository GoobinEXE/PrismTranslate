import XCTest

@testable import Prism

final class CustomHTTPParsingTests: XCTestCase {
    private func json(_ string: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(string.utf8))
    }

    func testExtractsTopLevelKey() throws {
        let payload = try json(#"{"translatedText": "Hello"}"#)
        XCTAssertEqual(CustomHTTPProvider.extract(path: "translatedText", from: payload), "Hello")
    }

    func testExtractsNestedPathWithArrayIndex() throws {
        // Formato idêntico ao do Google Translate v2.
        let payload = try json(#"""
        {"data": {"translations": [{"translatedText": "Olá"}, {"translatedText": "Oi"}]}}
        """#)
        XCTAssertEqual(
            CustomHTTPProvider.extract(path: "data.translations.0.translatedText", from: payload),
            "Olá"
        )
        XCTAssertEqual(
            CustomHTTPProvider.extract(path: "data.translations.1.translatedText", from: payload),
            "Oi"
        )
    }

    func testExtractsNumberAsString() throws {
        let payload = try json(#"{"result": 42}"#)
        XCTAssertEqual(CustomHTTPProvider.extract(path: "result", from: payload), "42")
    }

    func testReturnsNilForMissingKey() throws {
        let payload = try json(#"{"translatedText": "Hello"}"#)
        XCTAssertNil(CustomHTTPProvider.extract(path: "missing", from: payload))
    }

    func testReturnsNilForOutOfBoundsIndex() throws {
        let payload = try json(#"{"items": ["a"]}"#)
        XCTAssertNil(CustomHTTPProvider.extract(path: "items.5", from: payload))
    }

    func testReturnsNilWhenPathHitsNonContainer() throws {
        let payload = try json(#"{"text": "flat"}"#)
        XCTAssertNil(CustomHTTPProvider.extract(path: "text.deeper", from: payload))
    }

    func testReturnsNilWhenLeafIsObject() throws {
        let payload = try json(#"{"data": {"nested": true}}"#)
        // Bool em JSONSerialization vira NSNumber — documentando o comportamento atual:
        // folhas numéricas/booleanas são convertidas para string.
        XCTAssertEqual(CustomHTTPProvider.extract(path: "data.nested", from: payload), "1")
        XCTAssertNil(CustomHTTPProvider.extract(path: "data", from: payload))
    }

    func testNumericDictionaryKeyStillResolves() throws {
        // Chave "0" em objeto (não array) deve resolver pelo dicionário.
        let payload = try json(#"{"0": "zero"}"#)
        XCTAssertEqual(CustomHTTPProvider.extract(path: "0", from: payload), "zero")
    }

    func testJsonEscapeHandlesControlCharacters() {
        XCTAssertEqual(CustomHTTPProvider.jsonEscape("a\tb"), "a\\tb")
        XCTAssertEqual(CustomHTTPProvider.jsonEscape("a\rb"), "a\\rb")
        XCTAssertEqual(CustomHTTPProvider.jsonEscape("say \"hi\""), "say \\\"hi\\\"")
        XCTAssertEqual(CustomHTTPProvider.jsonEscape("line\nbreak"), "line\\nbreak")
    }

    func testJsonEscapeStripsNUL() {
        XCTAssertEqual(CustomHTTPProvider.jsonEscape("a\u{0000}b"), "ab")
    }

    func testHeadersContainCredentialsDetectsAuthorization() {
        let json = #"{"Authorization":"Bearer secret","Content-Type":"application/json"}"#
        XCTAssertTrue(CustomHTTPProvider.headersContainCredentials(json))
    }
}
