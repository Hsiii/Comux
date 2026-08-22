#if DEBUG
import XCTest
@testable import Comux

final class FreshDebugModeTests: XCTestCase {
    func testRequiresExplicitFreshEnvironmentValue() {
        XCTAssertTrue(FreshDebugMode.isEnabled(environment: ["FRESH": "1"]))
        XCTAssertFalse(FreshDebugMode.isEnabled(environment: ["FRESH": "0"]))
        XCTAssertFalse(FreshDebugMode.isEnabled(environment: [:]))
    }

    func testInitialCacheOffersResetCountdown() throws {
        let now = ISO8601DateFormatter().date(from: "2026-08-22T12:00:00Z")!
        let account = try XCTUnwrap(FreshDebugMode.initialCache(now: now).accounts.first)

        XCTAssertTrue(shouldOfferResetCountdown(for: account, now: now))
        XCTAssertEqual(usageWindowResetText(for: account.primaryUsageWindow, now: now), "Fresh")
    }

    func testStartedCacheShowsRunningCountdown() throws {
        let now = ISO8601DateFormatter().date(from: "2026-08-22T12:00:00Z")!
        let account = try XCTUnwrap(FreshDebugMode.startedCache(now: now).accounts.first)

        XCTAssertFalse(shouldOfferResetCountdown(for: account, now: now))
        XCTAssertEqual(account.primaryUsageWindow.usedPercentage, 1)
        XCTAssertTrue(usageWindowResetText(for: account.primaryUsageWindow, now: now).hasPrefix("Resets in "))
    }
}
#endif
