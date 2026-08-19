import XCTest

@testable import Prism

final class GoogleTranslateProviderTests: XCTestCase {
    func testMakeRequestUsesHeaderNotQueryKey() {
        let request = GoogleTranslateProvider.makeRequest(
            apiKey: SensitiveData("test-key"),
            text: "Hello",
            from: "en",
            to: "pt"
        )
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        XCTAssertNil(components?.queryItems)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Api-Key"), "test-key")
    }

    func testMakeRequestURLIsFixedEndpoint() {
        let request = GoogleTranslateProvider.makeRequest(
            apiKey: SensitiveData("k"),
            text: "x",
            from: nil,
            to: "en"
        )
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://translation.googleapis.com/language/translate/v2"
        )
    }
}
