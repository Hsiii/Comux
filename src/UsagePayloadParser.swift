import Foundation

enum UsagePayloadParser {
    static func parse(
        data: Data,
        response: URLResponse?
    ) throws -> [String: Any] {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw PulseError.invalidUsageResponse
        }

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PulseError.invalidUsageResponse
        }

        if payload["error"] != nil, payload["rate_limit"] as? [String: Any] == nil {
            throw PulseError.invalidUsageResponse
        }

        let hasIdentityFields = payload["account_id"] != nil
            || payload["email"] != nil
            || payload["plan_type"] != nil
        let hasUsageFields = payload["rate_limit"] as? [String: Any] != nil

        guard hasIdentityFields || hasUsageFields else {
            throw PulseError.invalidUsageResponse
        }

        return payload
    }
}

enum UsageWindowPayloadParser {
    static func parse(rateLimit: [String: Any]?) -> [UsageWindow] {
        guard let rateLimit else {
            return []
        }

        let preferredKeys = ["primary_window", "secondary_window"]
        let additionalKeys = rateLimit.keys
            .filter { $0.hasSuffix("_window") && !preferredKeys.contains($0) }
            .sorted()

        return (preferredKeys + additionalKeys).compactMap { key in
            guard let rawWindow = rateLimit[key] as? [String: Any] else {
                return nil
            }

            return Self.buildWindow(id: key, rawWindow: rawWindow)
        }
    }

    private static func buildWindow(
        id: String,
        rawWindow: [String: Any]
    ) -> UsageWindow {
        let durationSeconds = (rawWindow["limit_window_seconds"] as? NSNumber)?.intValue
        let resetAtEpoch = (rawWindow["reset_at"] as? NSNumber)?.doubleValue
        let usedPercent = clampPercentage((rawWindow["used_percent"] as? NSNumber)?.doubleValue ?? 0)
        let limitMinutes = Int(round(Double(durationSeconds ?? 0) / 60))
        let usedMinutes = Int(round(Double(limitMinutes) * (usedPercent / 100)))
        let resetsAt = resetAtEpoch.flatMap { epoch in
            epoch > 0 ? Date(timeIntervalSince1970: epoch).ISO8601Format() : nil
        } ?? ""

        return UsageWindow(
            id: id,
            scope: Self.scope(for: durationSeconds),
            durationSeconds: durationSeconds,
            available: true,
            label: Self.label(for: durationSeconds),
            usedMinutes: usedMinutes,
            limitMinutes: limitMinutes,
            usedPercentage: usedPercent,
            resetsAt: resetsAt
        )
    }

    private static func scope(for durationSeconds: Int?) -> UsageWindowScope {
        guard let durationSeconds, durationSeconds > 0 else {
            return .unknown
        }

        return durationSeconds >= 6 * 24 * 60 * 60 ? .longHorizon : .shortHorizon
    }

    private static func label(for durationSeconds: Int?) -> String {
        guard let durationSeconds, durationSeconds > 0 else {
            return "Usage window"
        }

        let day = 24 * 60 * 60
        let hour = 60 * 60

        if durationSeconds == 7 * day {
            return "Weekly window"
        }

        if durationSeconds.isMultiple(of: day) {
            return "\(durationSeconds / day)-day window"
        }

        if durationSeconds.isMultiple(of: hour) {
            return "\(durationSeconds / hour)-hour window"
        }

        return "Usage window"
    }
}

enum ResetCreditsPayloadParser {
    static func parse(
        data: Data,
        response: URLResponse?,
        now: Date = Date()
    ) throws -> CodexResetCredits {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw PulseError.invalidUsageResponse
        }

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PulseError.invalidUsageResponse
        }

        let rawAvailableCount = max((payload["available_count"] as? NSNumber)?.intValue ?? 0, 0)
        let rawCredits = payload["credits"] as? [[String: Any]] ?? []
        let availableCredits = rawCredits.compactMap { credit -> Date?? in
            guard (credit["status"] as? String) == "available" else {
                return nil
            }

            guard let expiresAt = Self.date(from: credit["expires_at"] as? String) else {
                return .some(nil)
            }

            return expiresAt > now ? .some(expiresAt) : nil
        }
        let availableCount = rawCredits.isEmpty ? rawAvailableCount : availableCredits.count
        let nextExpiresAt = availableCredits.compactMap { $0 }.min()?.ISO8601Format()

        return CodexResetCredits(
            availableCount: availableCount,
            nextExpiresAt: nextExpiresAt,
            updatedAt: now.ISO8601Format()
        )
    }

    private static func date(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}
