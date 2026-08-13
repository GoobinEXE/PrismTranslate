import XCTest
@testable import Prism

final class TranslationErrorHTTPTests: XCTestCase {
    func testDeepSeekInsufficientBalanceMapsToBillingMessage() {
        let body = #"{"error":{"message":"Insufficient Balance","type":"unknown_error","param":null,"code":"invalid_request_error"}}"#
        let message = TranslationError.userFacingHTTPMessage(statusCode: 402, body: body)
        XCTAssertTrue(message.contains("Saldo ou cota"))
        XCTAssertEqual(
            TranslationError.classifyHTTPFailure(statusCode: 402, body: body),
            .billingOrQuota
        )
    }

    func testOpenAIQuotaKeywordMapsToBillingEvenWithout402() {
        let body = #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota"}}"#
        XCTAssertEqual(
            TranslationError.classifyHTTPFailure(statusCode: 429, body: body),
            .billingOrQuota
        )
    }

    func testUnauthorized401() {
        let body = #"{"error":{"message":"Invalid API key"}}"#
        let message = TranslationError.userFacingHTTPMessage(statusCode: 401, body: body)
        XCTAssertTrue(message.contains("API key"))
    }

    func testExtractsOpenAIStyleMessageForOtherErrors() {
        let body = #"{"error":{"message":"Model not found"}}"#
        let message = TranslationError.userFacingHTTPMessage(statusCode: 404, body: body)
        XCTAssertTrue(message.contains("Modelo da API indisponível"))
    }

    func testGeminiLongModelUnavailableMessage() {
        let body = """
        {"error":{"code":404,"message":"This model models/gemini-2.5-flash is no longer available to new users. Please update your code to use a newer model for the latest features and improvements. We recommend you to use the Interactions API.","status":"NOT_FOUND"}}
        """
        let message = TranslationError.userFacingHTTPMessage(statusCode: 404, body: body)
        XCTAssertEqual(
            TranslationError.classifyHTTPFailure(statusCode: 404, body: body),
            .modelUnavailable
        )
        XCTAssertTrue(message.contains("Modelo da API indisponível"))
        XCTAssertFalse(message.contains("{\"error\""))
    }
}
