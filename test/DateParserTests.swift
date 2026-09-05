import Foundation
import XCTest
@testable import Comux

final class DateParserTests: XCTestCase {
    func testPreservesLegacyParsingIncludingInvalidAndOffsetValues() {
        for value in Self.values {
            XCTAssertEqual(parseISO8601Date(value), Self.legacyParse(value), value)
        }
    }

    func testConcurrentCallsDoNotMixFormatterState() {
        DispatchQueue.concurrentPerform(iterations: 500) { index in
            let value = Self.values[index % Self.values.count]
            XCTAssertEqual(parseISO8601Date(value), Self.legacyParse(value), value)
        }
    }

    private static let values = [
        "2026-09-05T12:34:56Z", "2026-09-05T12:34:56.123Z",
        "2026-09-05T12:34:56.123456Z", "2026-09-05T20:34:56+08:00",
        "2026-09-05T20:34:56.123+08:00", "2026-09-05T07:34:56-05:00",
        "2000-02-29T00:00:00Z", "", "invalid", "2026-09-05",
    ]

    private static func legacyParse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
