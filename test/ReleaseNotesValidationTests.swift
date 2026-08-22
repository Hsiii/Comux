import Foundation
import XCTest

final class ReleaseNotesValidationTests: XCTestCase {
    func testAcceptsGitHubCRLFReleaseNotes() throws {
        let result = try self.validate("## What's Changed\r\n\r\n- Add reset countdowns\r\n")

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.error.isEmpty)
    }

    func testRequiresChangesHeading() throws {
        let result = try self.validate("## Notes\n\n- Add reset countdowns\n")

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.error.contains("must contain an exact ## What's Changed heading"))
    }

    func testRequiresChangeBullet() throws {
        let result = try self.validate("## What's Changed\n\nNothing to report.\n")

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.error.contains("must include at least one bullet"))
    }

    private func validate(_ notes: String) throws -> (status: Int32, error: String) {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let script = testDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/validate-release-notes.sh")
        let process = Process()
        let input = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.standardInput = input
        process.standardError = error

        try process.run()
        input.fileHandleForWriting.write(Data(notes.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let errorText = String(
            decoding: error.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return (process.terminationStatus, errorText)
    }
}
