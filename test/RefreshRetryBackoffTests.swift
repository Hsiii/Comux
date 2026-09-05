import XCTest
@testable import Comux

final class RefreshRetryBackoffTests: XCTestCase {
    func testPersistentFailureRetriesBackOffToPeriodicRefreshCadence() {
        var backoff = RefreshRetryBackoff()
        XCTAssertEqual((0..<10).map { _ in backoff.takeDelay() },
                       [1, 2, 4, 8, 16, 32, 64, 120, 120, 120])
    }

    func testRecoveryRestoresFastSessionTransitionRetry() {
        var backoff = RefreshRetryBackoff()
        for _ in 0..<20 { _ = backoff.takeDelay() }
        backoff.reset()
        XCTAssertEqual(backoff.takeDelay(), 1)
        XCTAssertEqual(backoff.takeDelay(), 2)
    }
}
