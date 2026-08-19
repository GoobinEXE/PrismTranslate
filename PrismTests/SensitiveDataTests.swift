import XCTest

@testable import Prism

final class SensitiveDataTests: XCTestCase {
    func testStoresAndReadsUTF8() {
        let data = SensitiveData("hello")
        XCTAssertEqual(data.utf8String(), "hello")
    }

    func testIsEmptyWhenBlank() {
        XCTAssertTrue(SensitiveData("").isEmpty)
        XCTAssertFalse(SensitiveData("x").isEmpty)
    }

    func testHTTPHostSecurityLocalHosts() {
        XCTAssertTrue(HTTPHostSecurity.isLocalHost("localhost"))
        XCTAssertTrue(HTTPHostSecurity.isLocalHost("127.0.0.1"))
        XCTAssertTrue(HTTPHostSecurity.isLocalHost("::1"))
        XCTAssertFalse(HTTPHostSecurity.isLocalHost("api.example.com"))
    }
}
