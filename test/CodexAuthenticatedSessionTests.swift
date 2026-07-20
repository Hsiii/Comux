import XCTest
@testable import Comux

final class CodexAuthenticatedSessionTests: XCTestCase {
    func testConfigurationIsEphemeralAndCookieFree() {
        let configuration = CodexAuthenticatedSession.makeConfiguration()

        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCredentialStorage)
    }
}
