import XCTest
@testable import Comux

final class AutoUpdateTests: XCTestCase {
    func testVersionComparisonHandlesBasicSemver() {
        XCTAssertLessThan(AutoUpdateVersion("0.1.9"), AutoUpdateVersion("0.2.0"))
        XCTAssertLessThan(AutoUpdateVersion("v1.9.0"), AutoUpdateVersion("1.10.0"))
        XCTAssertEqual(AutoUpdateVersion("1.2.0"), AutoUpdateVersion("v1.2.0"))
    }

    func testVersionComparisonTreatsPrereleaseAsOlderThanRelease() {
        XCTAssertLessThan(AutoUpdateVersion("1.0.0-beta.2"), AutoUpdateVersion("1.0.0-beta.11"))
        XCTAssertLessThan(AutoUpdateVersion("1.0.0-beta.11"), AutoUpdateVersion("1.0.0"))
    }

    func testCaskParserExtractsSHA256() {
        let cask = """
        cask "comux" do
          version "0.2.0"
          sha256 "ABCDEF1234"
        end
        """

        XCTAssertEqual(AutoUpdateCaskParser.extractSHA256(from: cask), "abcdef1234")
    }

    func testUpdateMenuPresentationHighlightsOnlyAvailableUpdates() {
        XCTAssertEqual(AutoUpdateStatus.idle.menuTitle, "Latest Version Installed")
        XCTAssertTrue(AutoUpdateStatus.idle.isMenuRowDimmed)

        let candidate = AutoUpdateCandidate(
            version: "1.2.3",
            pageURL: URL(string: "https://example.com/release")!,
            archiveURL: URL(string: "https://example.com/comux.zip")!,
            expectedSHA256: "abc123"
        )
        let availableStatus = AutoUpdateStatus.updateAvailable(candidate)

        XCTAssertEqual(availableStatus.menuTitle, "Update Available")
        XCTAssertFalse(availableStatus.isMenuRowDimmed)
    }
}
