import XCTest
@testable import CodexMux

final class SystemRefreshErrorPolicyTests: XCTestCase {
    func testTreatsInvalidAuthFileAsRefreshedSystemState() {
        XCTAssertTrue(
            SystemRefreshErrorPolicy.shouldTreatAsRefreshedSystemState(
                PulseError.invalidAuthFile
            )
        )
    }

    func testDoesNotTreatWorkspaceListFailureAsRefreshedSystemState() {
        XCTAssertFalse(
            SystemRefreshErrorPolicy.shouldTreatAsRefreshedSystemState(
                PulseError.workspaceListUnavailable
            )
        )
    }

    func testDoesNotTreatNonPulseErrorsAsRefreshedSystemState() {
        XCTAssertFalse(
            SystemRefreshErrorPolicy.shouldTreatAsRefreshedSystemState(
                NSError(domain: "CodexMuxTests", code: 1)
            )
        )
    }
}
