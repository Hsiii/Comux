import XCTest
@testable import Comux

final class UsageHistoryTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testRecordsFirstSampleThenUsesIntervalOrMeaningfulChange() {
        let start = date("2026-07-18T00:00:00Z")
        let window = weeklyWindow(usedPercentage: 20)
        let previous = sample(at: start, usedPercentage: 20)

        XCTAssertTrue(UsageHistory.shouldRecord(previous: nil, window: window, sampledAt: start))
        XCTAssertFalse(UsageHistory.shouldRecord(
            previous: previous,
            window: weeklyWindow(usedPercentage: 20.5),
            sampledAt: start.addingTimeInterval(10 * 60)
        ))
        XCTAssertTrue(UsageHistory.shouldRecord(
            previous: previous,
            window: weeklyWindow(usedPercentage: 21),
            sampledAt: start.addingTimeInterval(10 * 60)
        ))
        XCTAssertTrue(UsageHistory.shouldRecord(
            previous: previous,
            window: window,
            sampledAt: start.addingTimeInterval(30 * 60)
        ))
    }

    func testUsedTodayUsesSampleAtStartOfDay() {
        let now = date("2026-07-18T12:00:00Z")
        let samples = [
            sample(at: date("2026-07-17T23:50:00Z"), usedPercentage: 20),
            sample(at: date("2026-07-18T08:00:00Z"), usedPercentage: 25),
            sample(at: now, usedPercentage: 28),
        ]

        XCTAssertEqual(
            UsageHistory.usedTodayPercentage(
                window: weeklyWindow(usedPercentage: 28),
                sampledAt: now,
                samples: samples,
                now: now,
                calendar: calendar
            ),
            8
        )
    }

    func testUsedTodayWaitsForSecondSampleWithoutMidnightBaseline() {
        let now = date("2026-07-18T12:00:00Z")
        let samples = [sample(at: now, usedPercentage: 28)]

        XCTAssertNil(UsageHistory.usedTodayPercentage(
            window: weeklyWindow(usedPercentage: 28),
            sampledAt: now,
            samples: samples,
            now: now,
            calendar: calendar
        ))
    }

    func testUsedTodayUsesCurrentWindowWhenItResetToday() {
        let now = date("2026-07-18T12:00:00Z")
        let window = UsageWindow(
            id: "weekly",
            scope: .longHorizon,
            durationSeconds: 7 * 24 * 60 * 60,
            available: true,
            label: "Weekly window",
            usedMinutes: 6,
            limitMinutes: 100,
            usedPercentage: 6,
            resetsAt: "2026-07-25T08:00:00Z"
        )

        XCTAssertEqual(
            UsageHistory.usedTodayPercentage(
                window: window,
                sampledAt: now,
                samples: [],
                now: now,
                calendar: calendar
            ),
            6
        )
    }

    func testUsedTodayHidesStaleSnapshot() {
        let now = date("2026-07-18T12:00:00Z")

        XCTAssertNil(UsageHistory.usedTodayPercentage(
            window: weeklyWindow(usedPercentage: 28),
            sampledAt: date("2026-07-17T23:00:00Z"),
            samples: [],
            now: now,
            calendar: calendar
        ))
    }

    private func weeklyWindow(usedPercentage: Double) -> UsageWindow {
        UsageWindow(
            id: "weekly",
            scope: .longHorizon,
            durationSeconds: 7 * 24 * 60 * 60,
            available: true,
            label: "Weekly window",
            usedMinutes: Int(usedPercentage),
            limitMinutes: 100,
            usedPercentage: usedPercentage,
            resetsAt: "2026-07-23T00:00:00Z"
        )
    }

    private func sample(at sampledAt: Date, usedPercentage: Double) -> UsageSample {
        UsageSample(
            accountID: "account",
            windowID: "weekly",
            sampledAt: sampledAt,
            usedPercentage: usedPercentage,
            resetsAt: "2026-07-23T00:00:00Z"
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
