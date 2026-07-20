import XCTest
@testable import Comux

final class WorkspaceLabelResolverTests: XCTestCase {
    func testReturnsNilWhenWorkspaceAccountIDIsMissing() {
        let label = WorkspaceLabelResolver.resolve(
            workspaceItems: [
                WorkspaceItem(id: "workspace-a", name: "Workspace A")
            ],
            workspaceAccountID: nil,
            normalizeWorkspaceAccountID: self.normalizeWorkspaceAccountID
        )

        XCTAssertNil(label)
    }

    func testReturnsMatchingWorkspaceLabelWhenWorkspaceAccountIDExists() {
        let label = WorkspaceLabelResolver.resolve(
            workspaceItems: [
                WorkspaceItem(id: "workspace-a", name: "Workspace A"),
                WorkspaceItem(id: "workspace-b", name: "Workspace B")
            ],
            workspaceAccountID: "WORKSPACE-B",
            normalizeWorkspaceAccountID: self.normalizeWorkspaceAccountID
        )

        XCTAssertEqual(label, "Workspace B")
    }

    func testStorageKeysKeepWorkspaceAndNoWorkspaceVariantsDistinct() {
        let workspaceKey = AccountIdentity.storageKey(
            email: "person@example.com",
            workspaceId: "workspace-a",
            workspaceLabel: "Workspace A"
        )
        let noWorkspaceKey = AccountIdentity.storageKey(
            email: "person@example.com",
            workspaceId: nil,
            workspaceLabel: ""
        )

        XCTAssertNotEqual(workspaceKey, noWorkspaceKey)
        XCTAssertEqual(noWorkspaceKey, "person@example.com")
    }

    func testWorkspaceListRequestUsesAccountScopedOAuthContext() {
        let request = WorkspaceLabelResolver.workspaceListRequest(
            accessToken: "access-token",
            cookieHeader: nil,
            accountHeader: "account-live"
        )

        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-live")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "codex-cli")
    }

    private func normalizeWorkspaceAccountID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed.lowercased()
    }
}
