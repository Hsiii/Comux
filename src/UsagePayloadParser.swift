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
