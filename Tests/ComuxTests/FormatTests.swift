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

    func testMenuBarUsageTextUsesTopRankedRollingWindowPercentage() {
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

        XCTAssertEqual(menuBarUsageText(from: [lowerRankedAccount, topAccount]), "65%")
    }

    func testMenuBarUsageTextPrefersCurrentSystemRollingWindow() {
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

        XCTAssertEqual(menuBarUsageText(from: [staleTopRankedAccount, currentAccount]), "28%")
    }
}
