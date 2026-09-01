import XCTest
@testable import Comux

final class RefreshFreshnessPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRefreshesWithoutACompletedSync() {
        XCTAssertTrue(
            RefreshFreshnessPolicy.shouldRefresh(
                lastCompletedAt: nil,
                now: self.now,
                maximumAge: 30
            )
        )
    }

    func testSkipsFreshCompletedSync() {
        XCTAssertFalse(
            RefreshFreshnessPolicy.shouldRefresh(
                lastCompletedAt: self.now.addingTimeInterval(-29),
                now: self.now,
                maximumAge: 30
            )
        )
    }

    func testRefreshesAtMaximumAge() {
        XCTAssertTrue(
            RefreshFreshnessPolicy.shouldRefresh(
                lastCompletedAt: self.now.addingTimeInterval(-30),
                now: self.now,
                maximumAge: 30
            )
        )
    }
}
