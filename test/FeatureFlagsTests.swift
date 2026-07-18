import XCTest
@testable import Comux

final class FeatureFlagsTests: XCTestCase {
    func testFiveHourLimitSupportDefaultsToDisabled() {
        XCTAssertFalse(FeatureFlags.fiveHourLimitSupportEnabled(environment: [:]))
    }

    func testFiveHourLimitSupportAcceptsTruthyEnvironmentValues() {
        for value in ["1", "true", "TRUE", "yes", "on"] {
            XCTAssertTrue(
                FeatureFlags.fiveHourLimitSupportEnabled(
                    environment: ["COMUX_SUPPORTS_FIVE_HOUR_LIMIT": value]
                )
            )
        }
    }

    func testFiveHourLimitSupportRejectsOtherEnvironmentValues() {
        for value in ["0", "false", "no", "off", "unexpected"] {
            XCTAssertFalse(
                FeatureFlags.fiveHourLimitSupportEnabled(
                    environment: ["COMUX_SUPPORTS_FIVE_HOUR_LIMIT": value]
                )
            )
        }
    }
}
