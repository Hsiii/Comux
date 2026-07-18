import XCTest
@testable import Comux

final class FormatTests: XCTestCase {
    func testUnavailableUsageWindowShowsNoSeatText() {
        let window = UsageWindow(
            available: false,
            label: "Weekly window",
            usedMinutes: 0,
            limitMinutes: 0,
            usedPercentage: 0,
            resetsAt: ""
        )

        XCTAssertEqual(percentageText(for: window), "No seat")
        XCTAssertEqual(resetPaceText(for: window), "No usage access")
    }

    func testExhaustedUsageWindowShowsUsedUpPaceText() {
        let resetDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
        let window = UsageWindow(
            available: true,
            label: "Weekly window",
            usedMinutes: 120,
            limitMinutes: 100,
            usedPercentage: 120,
            resetsAt: ISO8601DateFormatter().string(from: resetDate)
        )

        XCTAssertEqual(percentageText(for: window), "0%")
        XCTAssertTrue(resetPaceText(for: window).hasPrefix("Used up • Resets in "))
        XCTAssertFalse(resetPaceText(for: window).contains("-100%"))
    }

    func testUsageHeadlineCombinesRemainingWithCurrentMinusExpected() {
        let now = ISO8601DateFormatter().date(from: "2026-07-18T00:00:00Z")!
        let window = UsageWindow(
            id: "weekly",
            scope: .longHorizon,
            durationSeconds: 7 * 24 * 60 * 60,
            available: true,
            label: "Weekly window",
            usedMinutes: 20,
            limitMinutes: 100,
            usedPercentage: 20,
            resetsAt: "2026-07-23T00:00:00Z"
        )

        XCTAssertEqual(usageHeadlineText(for: window, now: now), "80% (+9%)")
    }

    func testFreshUsageWindowOmitsVarianceAndShowsFreshResetState() {
        let now = ISO8601DateFormatter().date(from: "2026-07-18T00:00:00Z")!
        let window = UsageWindow(
            id: "weekly",
            scope: .longHorizon,
            durationSeconds: 7 * 24 * 60 * 60,
            available: true,
            label: "Weekly window",
            usedMinutes: 0,
            limitMinutes: 100,
            usedPercentage: 0,
            resetsAt: "2026-07-17T00:00:00Z"
        )

        XCTAssertEqual(usageHeadlineText(for: window, now: now), "100%")
        XCTAssertEqual(usageWindowResetText(for: window, now: now), "Fresh")
    }

    func testFullUsageWindowOmitsVarianceBeforeItsReset() {
        let now = ISO8601DateFormatter().date(from: "2026-07-18T00:00:00Z")!
        let window = UsageWindow(
            id: "weekly",
            scope: .longHorizon,
            durationSeconds: 7 * 24 * 60 * 60,
            available: true,
            label: "Weekly window",
            usedMinutes: 0,
            limitMinutes: 100,
            usedPercentage: 0,
            resetsAt: "2026-07-24T00:00:00Z"
        )

        XCTAssertEqual(usageHeadlineText(for: window, now: now), "100%")
        XCTAssertEqual(usageWindowResetText(for: window, now: now), "Resets in 6d 0h")
    }

    func testCompactResetCreditsIncludesNextExpiry() {
        let now = ISO8601DateFormatter().date(from: "2026-07-18T00:00:00Z")!
        let resetCredits = CodexResetCredits(
            availableCount: 2,
            nextExpiresAt: "2026-07-20T03:00:00Z",
            updatedAt: "2026-07-18T00:00:00Z"
        )

        XCTAssertEqual(
            compactResetCreditsText(for: resetCredits, now: now),
            "2 resets • next expires in 2d 3h"
        )
        XCTAssertEqual(compactResetCreditsText(for: nil, now: now), "No resets")
    }

    func testThirtyDayUsageWindowAlignsPaceWithMonthlyReset() {
        let resetDate = Date().addingTimeInterval(24 * 24 * 60 * 60)
        let window = UsageWindow(
            available: true,
            label: "30-day window",
            usedMinutes: 8_640,
            limitMinutes: 43_200,
            usedPercentage: 20,
            resetsAt: ISO8601DateFormatter().string(from: resetDate)
        )

        XCTAssertEqual(displayWindowLabel(for: window), "30d")
        XCTAssertEqual(percentageText(for: window), "80%")
        XCTAssertEqual(currentExpectationDelta(for: window), 0)
    }

    func testPrimaryWindowExhaustionHidesShortHorizonLockCountdown() {
        let account = AccountSnapshot(
            accountId: "used-up",
            label: "Used Up",
            email: "used-up@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: true,
            lastSyncedAt: "2026-06-15T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 100,
                limitMinutes: 100,
                usedPercentage: 100,
                resetsAt: "2099-06-22T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 100,
                limitMinutes: 100,
                usedPercentage: 100,
                resetsAt: "2099-06-15T05:00:00Z"
            )
        )

        XCTAssertFalse(shouldShowShortHorizonLock(for: account))
    }

    func testShortHorizonLockStillShowsWhenPrimaryUsageRemains() {
        let account = AccountSnapshot(
            accountId: "session-locked",
            label: "Short Window Locked",
            email: "session-locked@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: true,
            lastSyncedAt: "2026-06-15T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 40,
                limitMinutes: 100,
                usedPercentage: 40,
                resetsAt: "2099-06-22T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 100,
                limitMinutes: 100,
                usedPercentage: 100,
                resetsAt: "2099-06-15T05:00:00Z"
            )
        )

        XCTAssertTrue(shouldShowShortHorizonLock(for: account, supportsFiveHourLimit: true))
        XCTAssertFalse(shouldShowShortHorizonLock(for: account, supportsFiveHourLimit: false))
    }

    func testMenuBarUsageTextUsesCurrentAccountLongHorizonPercentage() {
        let topAccount = AccountSnapshot(
            accountId: "top",
            label: "Top",
            email: "top@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: true,
            lastSyncedAt: "2026-06-12T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 70,
                limitMinutes: 100,
                usedPercentage: 70,
                resetsAt: "2099-06-19T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 35,
                limitMinutes: 100,
                usedPercentage: 35,
                resetsAt: "2099-06-12T05:00:00Z"
            )
        )
        let lowerRankedAccount = AccountSnapshot(
            accountId: "lower",
            label: "Lower",
            email: "lower@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: false,
            lastSyncedAt: "2026-06-12T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 80,
                limitMinutes: 100,
                usedPercentage: 80,
                resetsAt: "2099-06-18T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 10,
                limitMinutes: 100,
                usedPercentage: 10,
                resetsAt: "2099-06-12T05:00:00Z"
            )
        )

        XCTAssertEqual(menuBarUsageText(from: [lowerRankedAccount, topAccount]), "30% (-70%)")
    }

    func testMenuBarUsageTextPrefersCurrentSystemPrimaryWindow() {
        let staleTopRankedAccount = AccountSnapshot(
            accountId: "stale",
            label: "Stale",
            email: "stale@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: false,
            lastSyncedAt: "2026-06-12T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 10,
                limitMinutes: 100,
                usedPercentage: 10,
                resetsAt: "2099-06-19T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 100,
                limitMinutes: 100,
                usedPercentage: 100,
                resetsAt: "2026-06-12T05:00:00Z"
            )
        )
        let currentAccount = AccountSnapshot(
            accountId: "current",
            label: "Current",
            email: "current@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: true,
            lastSyncedAt: "2026-06-13T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 40,
                limitMinutes: 100,
                usedPercentage: 40,
                resetsAt: "2099-06-19T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 72,
                limitMinutes: 100,
                usedPercentage: 72,
                resetsAt: "2099-06-12T05:00:00Z"
            )
        )

        XCTAssertEqual(menuBarUsageText(from: [staleTopRankedAccount, currentAccount]), "60% (-40%)")
    }

    func testMenuBarUsageTextHidesWhenNoAccountIsCurrent() {
        let loggedOutAccount = AccountSnapshot(
            accountId: "logged-out",
            label: "Logged Out",
            email: "logged-out@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: false,
            lastSyncedAt: "2026-06-13T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 40,
                limitMinutes: 100,
                usedPercentage: 40,
                resetsAt: "2099-06-19T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 25,
                limitMinutes: 100,
                usedPercentage: 25,
                resetsAt: "2099-06-12T05:00:00Z"
            )
        )
        let historicalAccount = AccountSnapshot(
            accountId: "historical",
            label: "Historical",
            email: "historical@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: nil,
            lastSyncedAt: "2026-06-12T00:00:00Z",
            weeklyWindow: UsageWindow(
                available: true,
                label: "Weekly window",
                usedMinutes: 10,
                limitMinutes: 100,
                usedPercentage: 10,
                resetsAt: "2099-06-19T00:00:00Z"
            ),
            rollingWindow: UsageWindow(
                available: true,
                label: "Rolling 5-hour window",
                usedMinutes: 5,
                limitMinutes: 100,
                usedPercentage: 5,
                resetsAt: "2099-06-12T05:00:00Z"
            )
        )

        XCTAssertNil(menuBarUsageText(from: [loggedOutAccount, historicalAccount]))
    }
}
