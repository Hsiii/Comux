import XCTest
@testable import Comux

final class BoundedConcurrencyTests: XCTestCase {
    func testLimitsConcurrencyAndPreservesInputOrder() async throws {
        let probe = ConcurrencyProbe()

        let results = try await BoundedConcurrency.map(
            Array(0..<6),
            limit: 2
        ) { value in
            await probe.enter()
            try await Task.sleep(for: .milliseconds(10 * (6 - value)))
            await probe.leave()
            return value
        }

        let maximumActive = await probe.maximumActive
        XCTAssertEqual(maximumActive, 2)
        XCTAssertEqual(results, Array(0..<6))
    }

    func testTreatsNonpositiveLimitAsOne() async throws {
        let probe = ConcurrencyProbe()

        _ = try await BoundedConcurrency.map(Array(0..<3), limit: 0) { value in
            await probe.enter()
            try await Task.sleep(for: .milliseconds(5))
            await probe.leave()
            return value
        }

        let maximumActive = await probe.maximumActive
        XCTAssertEqual(maximumActive, 1)
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0

    func enter() {
        self.active += 1
        self.maximumActive = max(self.maximumActive, self.active)
    }

    func leave() {
        self.active -= 1
    }
}
