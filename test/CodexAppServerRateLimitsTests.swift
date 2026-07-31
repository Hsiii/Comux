import XCTest
@testable import Comux

final class CodexAppServerRateLimitsTests: XCTestCase {
    func testParsesWeeklyOnlySnapshotAndAuthoritativeResetCount() throws {
        let now = ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!
        let snapshot = CodexAppServerRateLimitsParser.parse(
            [
                "result": [
                    "rateLimits": [
                        "primary": [
                            "usedPercent": 25,
                            "windowDurationMins": 10_080,
                            "resetsAt": 1_783_036_800,
                        ],
                        "secondary": NSNull(),
                    ],
                    "rateLimitResetCredits": [
                        "availableCount": 3,
                        "credits": [
                            [
                                "status": "available",
                                "expiresAt": 1_784_246_400,
                            ],
                        ],
                    ],
                ],
            ],
            now: now
        )

        let resolved = try XCTUnwrap(snapshot)
        XCTAssertEqual(resolved.usageWindows.count, 1)
        XCTAssertEqual(resolved.usageWindows[0].scope, .longHorizon)
        XCTAssertEqual(resolved.usageWindows[0].durationSeconds, 7 * 24 * 60 * 60)
        XCTAssertEqual(resolved.usageWindows[0].usedPercentage, 25)
        XCTAssertEqual(resolved.resetCredits?.availableCount, 3)
        XCTAssertEqual(resolved.resetCredits?.nextExpiresAt, "2026-07-17T00:00:00Z")
    }

    func testParsesFiveHourAndWeeklyWindowsWithoutAssumingPositions() throws {
        let snapshot = CodexAppServerRateLimitsParser.parse([
            "result": [
                "rateLimits": [
                    "primary": [
                        "usedPercent": 60,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000,
                    ],
                    "secondary": [
                        "usedPercent": 20,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_800_604_800,
                    ],
                ],
                "rateLimitResetCredits": NSNull(),
            ],
        ])

        let resolved = try XCTUnwrap(snapshot)
        XCTAssertEqual(resolved.usageWindows.map(\.scope), [.shortHorizon, .longHorizon])
        XCTAssertEqual(resolved.usageWindows.map(\.durationSeconds), [18_000, 604_800])
        XCTAssertNil(resolved.resetCredits)
    }

    func testReaderCompletesAppServerHandshake() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("comux-app-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let executable = root.appendingPathComponent("codex", isDirectory: false)
        try """
        #!/bin/sh
        IFS= read -r initialize
        printf '{"id":1,"result":{}}\\n'
        IFS= read -r initialized
        IFS= read -r request
        printf '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":null},"rateLimitResetCredits":{"availableCount":1,"credits":[]}}}\\n'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let snapshot = CodexAppServerRateLimitsReader.read(
            executable: executable.path,
            timeout: 1,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(snapshot?.usageWindows.first?.usedPercentage, 12)
        XCTAssertEqual(snapshot?.usageWindows.first?.durationSeconds, 604_800)
        XCTAssertEqual(snapshot?.resetCredits?.availableCount, 1)
    }
}
