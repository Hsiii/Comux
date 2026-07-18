import Foundation

struct UsageSample: Equatable {
    let accountID: String
    let windowID: String
    let sampledAt: Date
    let usedPercentage: Double
    let resetsAt: String
}

enum UsageHistory {
    static let sampleInterval: TimeInterval = 30 * 60
    static let sampleChangeThreshold = 1.0
    static let retentionInterval: TimeInterval = 8 * 24 * 60 * 60

    static func shouldRecord(
        previous: UsageSample?,
        window: UsageWindow,
        sampledAt: Date
    ) -> Bool {
        guard window.available else {
            return false
        }

        guard let previous else {
            return true
        }

        guard sampledAt > previous.sampledAt else {
            return false
        }

        return previous.resetsAt != window.resetsAt
            || sampledAt.timeIntervalSince(previous.sampledAt) >= self.sampleInterval
            || abs(window.usedPercentage - previous.usedPercentage) >= self.sampleChangeThreshold
    }

    static func usedTodayPercentage(
        window: UsageWindow,
        sampledAt: Date,
        samples: [UsageSample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        guard window.available,
              sampledAt <= now,
              let durationSeconds = window.durationSeconds,
              durationSeconds > 0,
              let resetDate = parseISO8601Date(window.resetsAt)
        else {
            return nil
        }

        let startOfToday = calendar.startOfDay(for: now)
        guard sampledAt >= startOfToday else {
            return nil
        }

        let windowStart = resetDate.addingTimeInterval(-TimeInterval(durationSeconds))
        if windowStart >= startOfToday, windowStart <= sampledAt {
            return Int(round(clampPercentage(window.usedPercentage)))
        }

        let relevantSamples = samples
            .filter {
                $0.accountID.isEmpty == false
                    && $0.windowID == window.id
                    && $0.resetsAt == window.resetsAt
                    && $0.sampledAt <= sampledAt
            }
            .sorted { $0.sampledAt < $1.sampledAt }

        let baseline = relevantSamples.last(where: { $0.sampledAt <= startOfToday })
            ?? relevantSamples.first(where: { $0.sampledAt > startOfToday })

        guard let baseline, baseline.sampledAt < sampledAt else {
            return nil
        }

        let usedToday = max(0, window.usedPercentage - baseline.usedPercentage)
        return Int(round(clampPercentage(usedToday)))
    }
}
