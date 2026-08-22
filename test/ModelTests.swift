import XCTest
@testable import Comux

final class ModelTests: XCTestCase {
    func testLegacySnapshotDecodesIntoGenericUsageWindows() throws {
        let data = Data(
            """
            {
              "accountId": "person@example.com::personal",
              "label": "Person",
              "email": "person@example.com",
              "workspaceLabel": "Personal",
              "plan": "Codex Pro",
              "source": "test",
              "lastSyncedAt": "2026-07-18T00:00:00Z",
              "weeklyWindow": {
                "available": true,
                "label": "Weekly window",
                "usedMinutes": 10,
                "limitMinutes": 100,
                "usedPercentage": 10,
                "resetsAt": "2026-07-25T00:00:00Z"
              },
              "rollingWindow": {
                "available": false,
                "label": "Rolling 5-hour window",
                "usedMinutes": 0,
                "limitMinutes": 0,
                "usedPercentage": 0,
                "resetsAt": ""
              }
            }
            """.utf8
        )

        let snapshot = try JSONDecoder().decode(AccountSnapshot.self, from: data)

        XCTAssertEqual(snapshot.accountId, "person@example.com::personal")
        XCTAssertEqual(snapshot.usageWindows.count, 2)
        XCTAssertEqual(snapshot.longHorizonWindow?.id, "legacy-weekly")
        XCTAssertEqual(snapshot.longHorizonWindow?.durationSeconds, 7 * 24 * 60 * 60)
        XCTAssertEqual(snapshot.shortHorizonWindow?.id, "legacy-rolling")
    }

    func testGenericSnapshotRoundTripPreservesServerWindows() throws {
        let shortWindow = UsageWindow(
            id: "primary",
            scope: .shortHorizon,
            durationSeconds: 3 * 60 * 60,
            available: true,
            label: "3-hour window",
            usedMinutes: 30,
            limitMinutes: 180,
            usedPercentage: 16.7,
            resetsAt: "2026-07-18T03:00:00Z"
        )
        let longWindow = UsageWindow(
            id: "secondary",
            scope: .longHorizon,
            durationSeconds: 30 * 24 * 60 * 60,
            available: true,
            label: "30-day window",
            usedMinutes: 100,
            limitMinutes: 1_000,
            usedPercentage: 10,
            resetsAt: "2026-08-17T00:00:00Z"
        )
        let snapshot = AccountSnapshot(
            accountId: "person@example.com::personal",
            label: "Person",
            email: "person@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: true,
            lastSyncedAt: "2026-07-18T00:00:00Z",
            usageWindows: [shortWindow, longWindow],
            resetCredits: CodexResetCredits(
                availableCount: 2,
                nextExpiresAt: nil,
                updatedAt: "2026-07-18T00:00:00Z"
            )
        )

        let decoded = try JSONDecoder().decode(
            AccountSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.usageWindows, [shortWindow, longWindow])
        XCTAssertEqual(decoded.primaryUsageWindow.id, "secondary")
        XCTAssertEqual(decoded.accountId, snapshot.accountId)
        XCTAssertEqual(resetCreditsCountText(for: decoded.resetCredits), "2 resets available")
    }

    func testPrimaryWindowPrefersAvailableLongHorizon() {
        let availableWeekly = UsageWindow(
            id: "weekly",
            scope: .longHorizon,
            durationSeconds: 7 * 24 * 60 * 60,
            available: true,
            label: "Weekly window",
            usedMinutes: 10,
            limitMinutes: 100,
            usedPercentage: 10,
            resetsAt: "2026-07-25T00:00:00Z"
        )
        let unavailableMonthly = UsageWindow(
            id: "monthly",
            scope: .longHorizon,
            durationSeconds: 30 * 24 * 60 * 60,
            available: false,
            label: "30-day window",
            usedMinutes: 0,
            limitMinutes: 0,
            usedPercentage: 0,
            resetsAt: ""
        )
        let snapshot = AccountSnapshot(
            accountId: "person@example.com::personal",
            label: "Person",
            email: "person@example.com",
            workspaceId: nil,
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            source: "test",
            systemAuthProfileId: nil,
            isCurrentSystemAccount: true,
            lastSyncedAt: "2026-07-18T00:00:00Z",
            usageWindows: [unavailableMonthly, availableWeekly]
        )

        XCTAssertEqual(snapshot.primaryUsageWindow.id, "weekly")
    }
}
