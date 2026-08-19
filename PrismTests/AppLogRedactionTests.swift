import XCTest

@testable import Prism

final class AppLogRedactionTests: XCTestCase {
    override func tearDown() {
        AppLogPreferences.update(from: AppSettings())
        super.tearDown()
    }

    func testPreviewDefaultIsCharacterCountOnly() {
        var settings = AppSettings()
        settings.logTextPreviews = false
        AppLogPreferences.update(from: settings)
        let preview = AppLog.preview("mensagem secreta do usuário")
        XCTAssertTrue(preview.hasPrefix("("))
        XCTAssertTrue(preview.hasSuffix("caracteres)"))
        XCTAssertFalse(preview.contains("secreta"))
    }

    func testPreviewOptInIncludesTruncatedText() {
        var settings = AppSettings()
        settings.logTextPreviews = true
        AppLogPreferences.update(from: settings)
        XCTAssertTrue(AppLog.preview("hello world").contains("hello"))
    }

    func testRedactSecretsMasksBearerAndQueryKey() {
        let input = "Auth failed Bearer sk-live-abc ?key=supersecret"
        let redacted = AppLogStore.redactSecrets(in: input)
        XCTAssertFalse(redacted.contains("sk-live-abc"))
        XCTAssertFalse(redacted.contains("supersecret"))
        XCTAssertTrue(redacted.contains("Bearer ***"))
    }

    func testRedactSecretsMasksJSONTextField() {
        let input = #"{"text":"private chat message","target":"pt"}"#
        let redacted = AppLogStore.redactSecrets(in: input)
        XCTAssertFalse(redacted.contains("private chat message"))
        XCTAssertTrue(redacted.contains("\"text\": \"***\""))
    }

    func testHttpBodyPreviewRedactsSensitiveJSON() {
        let preview = AppLog.httpBodyPreview(#"{"text":"secret","Authorization":"Bearer tok"}"#)
        XCTAssertFalse(preview.contains("secret"))
        XCTAssertFalse(preview.contains("tok"))
    }
}
