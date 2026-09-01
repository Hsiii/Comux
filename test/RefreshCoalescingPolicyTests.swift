import XCTest
@testable import Comux

final class RefreshCoalescingPolicyTests: XCTestCase {
    func testDropsPassiveRequestDuringSync() {
        XCTAssertFalse(
            RefreshCoalescingPolicy.shouldQueueFollowUp(
                isSyncing: true,
                requestKind: .passive
            )
        )
    }

    func testQueuesStateChangeDuringSync() {
        XCTAssertTrue(
            RefreshCoalescingPolicy.shouldQueueFollowUp(
                isSyncing: true,
                requestKind: .stateChange
            )
        )
    }

    func testIdleRequestDoesNotNeedFollowUp() {
        XCTAssertFalse(
            RefreshCoalescingPolicy.shouldQueueFollowUp(
                isSyncing: false,
                requestKind: .stateChange
            )
        )
    }
}
