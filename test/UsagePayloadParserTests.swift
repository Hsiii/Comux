import XCTest
@testable import Comux

final class UsagePayloadParserTests: XCTestCase {
    func testRejectsNonSuccessStatusEvenWhenBodyIsJSON() throws {
        let data = try self.jsonData([
            "error": [
                "message": "unauthorized"
            ]
        ])
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )

        XCTAssertThrowsError(
            try UsagePayloadParser.parse(
                data: data,
                response: response
            )
        ) { error in
            XCTAssertEqual(error as? PulseError, .invalidUsageResponse)
        }
    }

    func testRejectsErrorPayloadsWithoutUsageFields() throws {
        let data = try self.jsonData([
            "error": [
                "message": "forbidden"
            ]
        ])
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        XCTAssertThrowsError(
            try UsagePayloadParser.parse(
                data: data,
                response: response
            )
        ) { error in
            XCTAssertEqual(error as? PulseError, .invalidUsageResponse)
        }
    }

    func testAcceptsUsagePayloadWithExpectedFields() throws {
        let data = try self.jsonData([
            "account_id": "workspace-a",
            "email": "person@example.com",
            "plan_type": "team",
            "rate_limit": [
                "primary_window": [
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_000,
                    "used_percent": 50
                ]
            ]
        ])
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let payload = try UsagePayloadParser.parse(
            data: data,
            response: response
        )

        XCTAssertEqual(payload["account_id"] as? String, "workspace-a")
        XCTAssertEqual(payload["email"] as? String, "person@example.com")
    }

    func testUsageWindowsFollowPayloadDurationsInsteadOfFixedPositions() {
        let windows = UsageWindowPayloadParser.parse(
            rateLimit: [
                "primary_window": [
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_800_000_000,
                    "used_percent": 50,
                ],
                "secondary_window": [
                    "limit_window_seconds": 604_800,
                    "reset_at": 1_800_604_800,
                    "used_percent": 25,
                ],
            ]
        )

        XCTAssertEqual(windows.map(\.id), ["primary_window", "secondary_window"])
        XCTAssertEqual(windows[0].scope, .shortHorizon)
        XCTAssertEqual(windows[0].label, "5-hour window")
        XCTAssertEqual(windows[0].durationSeconds, 18_000)
        XCTAssertEqual(windows[0].usedMinutes, 150)
        XCTAssertEqual(windows[1].scope, .longHorizon)
        XCTAssertEqual(windows[1].label, "Weekly window")
        XCTAssertEqual(windows[1].durationSeconds, 604_800)
    }

    func testUsageWindowsDoNotInventMissingShortWindow() {
        let windows = UsageWindowPayloadParser.parse(
            rateLimit: [
                "primary_window": [
                    "limit_window_seconds": 2_592_000,
                    "reset_at": 1_800_000_000,
                    "used_percent": 10,
                ],
            ]
        )

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].id, "primary_window")
        XCTAssertEqual(windows[0].scope, .longHorizon)
        XCTAssertEqual(windows[0].label, "30-day window")
    }

    func testUsageWindowsIncludeAdditionalServerWindowKeys() {
        let windows = UsageWindowPayloadParser.parse(
            rateLimit: [
                "burst_window": [
                    "limit_window_seconds": 3_600,
                    "reset_at": 1_800_000_000,
                    "used_percent": 5,
                ],
            ]
        )

        XCTAssertEqual(windows.map(\.id), ["burst_window"])
        XCTAssertEqual(windows[0].label, "1-hour window")
        XCTAssertEqual(windows[0].scope, .shortHorizon)
        XCTAssertEqual(displayWindowLabel(for: windows[0]), "1h")
    }

    func testParsesAvailableResetCreditsAndNextExpiry() throws {
        let data = try self.jsonData([
            "credits": [
                [
                    "id": "expired",
                    "reset_type": "codex_rate_limits",
                    "status": "available",
                    "granted_at": "2026-06-01T00:00:00Z",
                    "expires_at": "2026-06-20T00:00:00Z",
                ],
                [
                    "id": "later",
                    "reset_type": "codex_rate_limits",
                    "status": "available",
                    "granted_at": "2026-06-18T00:39:53.731630Z",
                    "expires_at": "2026-07-18T00:39:53.731630Z",
                ],
                [
                    "id": "earlier",
                    "reset_type": "codex_rate_limits",
                    "status": "available",
                    "granted_at": "2026-06-12T04:03:43.263391Z",
                    "expires_at": "2026-07-12T04:03:43.263391Z",
                ],
                [
                    "id": "redeemed",
                    "reset_type": "codex_rate_limits",
                    "status": "redeemed",
                    "granted_at": "2026-06-12T04:03:43Z",
                    "expires_at": "2026-07-10T04:03:43Z",
                ],
            ],
            "available_count": 2,
        ])
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        let now = ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!

        let resetCredits = try ResetCreditsPayloadParser.parse(
            data: data,
            response: response,
            now: now
        )

        XCTAssertEqual(resetCredits.availableCount, 2)
        XCTAssertEqual(resetCredits.nextExpiresAt, "2026-07-12T04:03:43Z")
    }

    func testResetCreditCountRemainsAuthoritativeWhenDetailsAreTruncated() throws {
        let data = try self.jsonData([
            "credits": [
                [
                    "id": "only-detail",
                    "status": "available",
                    "expires_at": "2026-07-18T00:39:53Z",
                ],
            ],
            "available_count": 3,
        ])
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let resetCredits = try ResetCreditsPayloadParser.parse(
            data: data,
            response: response,
            now: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!
        )

        XCTAssertEqual(resetCredits.availableCount, 3)
        XCTAssertEqual(resetCredits.nextExpiresAt, "2026-07-18T00:39:53Z")
    }

    func testExplicitZeroResetCountRemainsAuthoritative() throws {
        let data = try self.jsonData([
            "credits": [
                [
                    "id": "stale-detail",
                    "status": "available",
                    "expires_at": "2026-07-18T00:39:53Z",
                ],
            ],
            "available_count": 0,
        ])

        let resetCredits = try ResetCreditsPayloadParser.parse(
            data: data,
            response: nil,
            now: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!
        )

        XCTAssertEqual(resetCredits.availableCount, 0)
    }

    func testResetCreditSummaryShowsCountAndNextExpiry() {
        let resetCredits = CodexResetCredits(
            availableCount: 1,
            nextExpiresAt: Date().addingTimeInterval((2 * 24 * 60 * 60) + (3 * 60 * 60)).ISO8601Format(),
            updatedAt: Date().ISO8601Format()
        )

        XCTAssertEqual(
            resetCreditsSummaryText(for: resetCredits),
            "1 full reset available • next expires in 2d 2h"
        )
    }

    private func jsonData(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
}
