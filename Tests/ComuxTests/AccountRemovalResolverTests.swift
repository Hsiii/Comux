import XCTest
@testable import Comux

final class AccountRemovalResolverTests: XCTestCase {
    func testCacheOnlySystemAccountIsRemovable() {
        let account = self.makeSnapshot(
            accountId: "person@example.com::workspace-a",
            email: "person@example.com",
            workspaceId: "workspace-a",
            workspaceLabel: "Workspace A",
            source: "live system auth"
        )

        let removableIDs = AccountRemovalResolver.removableAccountIDs(
            for: [account]
        )

        XCTAssertEqual(removableIDs, Set([account.accountId]))
    }

    func testRemovingCacheOnlySystemAccountFiltersCacheAndKeepsConfig() {
        let removed = self.makeSnapshot(
            accountId: "person@example.com::workspace-a",
            email: "person@example.com",
            workspaceId: "workspace-a",
            workspaceLabel: "Workspace A",
            source: "live system auth"
        )
        let retained = self.makeSnapshot(
            accountId: "other@example.com::workspace-b",
            email: "other@example.com",
            workspaceId: "workspace-b",
            workspaceLabel: "Workspace B",
            source: "live system auth"
        )
        let configAccount = self.makeConfig(
            id: "cookie-account",
            email: "cookie@example.com",
            workspaceLabel: "Cookie Workspace",
            accountHeader: "cookie-workspace"
        )
        let cache = CachePayload(
            meta: CacheMeta(source: "test"),
            accounts: [removed, retained]
        )
        let config = PulseConfig(
            pollIntervalSeconds: 300,
            accounts: [configAccount]
        )

        let result = AccountRemovalResolver.remove(
            removed,
            from: cache,
            config: config
        )

        XCTAssertEqual(result.cache.accounts.map(\.accountId), [retained.accountId])
        XCTAssertEqual(result.config.accounts.map(\.id), [configAccount.id])
    }

    func testRemovingCookieAccountFiltersMatchingConfig() {
        let account = self.makeSnapshot(
            accountId: "person@example.com::workspace-a",
            email: "person@example.com",
            workspaceId: "workspace-a",
            workspaceLabel: "Workspace A",
            source: "native cookie sync"
        )
        let configAccount = self.makeConfig(
            id: "legacy-cookie-id",
            email: "person@example.com",
            workspaceLabel: "Workspace A",
            accountHeader: "workspace-a"
        )
        let cache = CachePayload(
            meta: CacheMeta(source: "test"),
            accounts: [account]
        )
        let config = PulseConfig(
            pollIntervalSeconds: 300,
            accounts: [configAccount]
        )

        let result = AccountRemovalResolver.remove(
            account,
            from: cache,
            config: config
        )

        XCTAssertTrue(result.cache.accounts.isEmpty)
        XCTAssertTrue(result.config.accounts.isEmpty)
    }

    private func makeSnapshot(
        accountId: String,
        email: String,
        workspaceId: String?,
        workspaceLabel: String,
        source: String
    ) -> AccountSnapshot {
        AccountSnapshot(
            accountId: accountId,
            label: email,
            email: email,
            workspaceId: workspaceId,
            workspaceLabel: workspaceLabel,
            plan: "Codex Pro",
            source: source,
            systemAuthProfileId: nil,
            isCurrentSystemAccount: false,
            lastSyncedAt: "2026-06-15T00:00:00Z",
            weeklyWindow: self.makeWindow(),
            rollingWindow: self.makeWindow()
        )
    }

    private func makeConfig(
        id: String,
        email: String,
        workspaceLabel: String,
        accountHeader: String?
    ) -> AccountConfig {
        AccountConfig(
            id: id,
            label: email,
            email: email,
            workspaceLabel: workspaceLabel,
            plan: "Codex Pro",
            color: "blue",
            chatGPTCookie: "cookie",
            source: "native cookie sync",
            sessionEndpoint: nil,
            usageEndpoint: nil,
            accountHeader: accountHeader
        )
    }

    private func makeWindow() -> UsageWindow {
        UsageWindow(
            available: true,
            label: "Weekly window",
            usedMinutes: 10,
            limitMinutes: 100,
            usedPercentage: 10,
            resetsAt: "2099-06-15T00:00:00Z"
        )
    }
}
