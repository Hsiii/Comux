import XCTest
@testable import Comux

final class RefreshPublicationPolicyTests: XCTestCase {
    func testPublishesRefreshedEmptySystemState() {
        XCTAssertTrue(
            RefreshPublicationPolicy.shouldPublish(
                snapshotCount: 0,
                systemStateWasRefreshed: true
            )
        )
    }

    func testPublishesIncomingSnapshotsWithoutSystemRefresh() {
        XCTAssertTrue(
            RefreshPublicationPolicy.shouldPublish(
                snapshotCount: 1,
                systemStateWasRefreshed: false
            )
        )
    }

    func testSkipsEmptyFailedRefresh() {
        XCTAssertFalse(
            RefreshPublicationPolicy.shouldPublish(
                snapshotCount: 0,
                systemStateWasRefreshed: false
            )
        )
    }
}
