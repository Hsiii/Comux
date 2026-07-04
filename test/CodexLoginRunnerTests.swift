import XCTest
@testable import Comux

final class CodexLoginRunnerTests: XCTestCase {
    func testReturnsMissingBinaryWhenCodexIsNotOnPath() async throws {
        let root = try self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let result = await CodexLoginRunner.run(
            timeout: 0.2,
            environment: ["PATH": root.path],
            additionalSearchPaths: []
        )

        XCTAssertEqual(result.outcome, .missingBinary)
        XCTAssertTrue(result.output.isEmpty)
    }

    func testRunsCodexLoginFromPath() async throws {
        let root = try self.makeTemporaryDirectory()
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let codex = bin.appendingPathComponent("codex", isDirectory: false)
        try """
        #!/bin/sh
        printf 'login ok\\n'
        """.write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: codex.path
        )

        let result = await CodexLoginRunner.run(
            timeout: 1,
            environment: ["PATH": bin.path],
            additionalSearchPaths: []
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(result.output.contains("login ok"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("comux-codex-login-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
