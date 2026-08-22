import XCTest
@testable import Comux

final class ResetCountdownTests: XCTestCase {
    func testRunsEphemeralLunaPromptWithRestrictedOptions() async throws {
        let root = try self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let argumentsFile = root.appendingPathComponent("arguments.txt", isDirectory: false)
        let executable = root.appendingPathComponent("codex", isDirectory: false)
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > "$ARGUMENTS_FILE"
        printf 'hi\\n'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let result = await ResetCountdownRunner.run(
            executable: executable.path,
            timeout: 1,
            environment: ["ARGUMENTS_FILE": argumentsFile.path, "PATH": "/usr/bin:/bin"]
        )
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.output, "hi\n")
        XCTAssertEqual(arguments.first, "exec")
        XCTAssertTrue(arguments.contains("gpt-5.6-luna"))
        XCTAssertTrue(arguments.contains("--ephemeral"))
        XCTAssertTrue(arguments.contains("--ignore-user-config"))
        XCTAssertTrue(arguments.contains("--ignore-rules"))
        XCTAssertTrue(arguments.contains("read-only"))
        XCTAssertTrue(arguments.contains("Reply with exactly hi. Do not use tools or inspect files."))
    }

    func testReportsFailedCodexInvocation() async throws {
        let root = try self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let executable = root.appendingPathComponent("codex", isDirectory: false)
        try """
        #!/bin/sh
        printf 'model unavailable\\n' >&2
        exit 7
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let result = await ResetCountdownRunner.run(
            executable: executable.path,
            timeout: 1,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(result.outcome, .failed(status: 7))
        XCTAssertEqual(result.output, "model unavailable\n")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("comux-reset-countdown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
