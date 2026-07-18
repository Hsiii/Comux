import Foundation
import SwiftUI

final class CacheStore {
    private let durableStore = DurableStoreCoordinator.shared
    private let snapshotMerger = AccountSnapshotMerger()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func load() -> CachePayload {
        let payload = self.durableStore.loadCache(
            fallback: self.emptyPayload()
        )

        let migratedPayload = self.compactLoadedAccounts(
            in: self.migrateLegacyAccounts(in: payload)
        )
        let migratedData = try? self.encoder.encode(migratedPayload)
        let originalData = try? self.encoder.encode(payload)

        if migratedData != originalData {
            try? self.save(migratedPayload)
        }

        return migratedPayload
    }

    func save(_ payload: CachePayload) throws {
        try self.durableStore.saveCache(
            payload,
            event: "cache.save"
        )
    }

    func usedTodayPercentages(
        for payload: CachePayload,
        now: Date = Date()
    ) -> [String: Int] {
        self.durableStore.loadUsedTodayPercentages(
            for: payload.accounts,
            now: now
        )
    }

    func removeAccount(withID accountID: String) throws -> CachePayload {
        let existing = self.load()
        let filteredAccounts = existing.accounts.filter { $0.accountId != accountID }
        let payload = CachePayload(
            meta: CacheMeta(
                source: existing.meta.source
            ),
            accounts: filteredAccounts
        )
        try self.save(payload)
        return payload
    }

    private func emptyPayload() -> CachePayload {
        CachePayload(
            meta: CacheMeta(
                source: "native-swift-cache"
            ),
            accounts: []
        )
    }

    private func migrateLegacyAccounts(in payload: CachePayload) -> CachePayload {
        var accountsByIdentity: [String: AccountSnapshot] = [:]

        for account in payload.accounts {
            let normalizedAccount = self.normalizedAccountIdentity(
                for: account
            )
            let prior = accountsByIdentity[normalizedAccount.accountId]
            accountsByIdentity[normalizedAccount.accountId] = self.preferredAccountSnapshot(
                current: prior,
                candidate: normalizedAccount
            )
        }

        let migratedAccounts = accountsByIdentity.values.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }

        return CachePayload(
            meta: CacheMeta(
                source: payload.meta.source
            ),
            accounts: migratedAccounts
        )
    }

    private func compactLoadedAccounts(in payload: CachePayload) -> CachePayload {
        self.snapshotMerger.merge(
            existing: CachePayload(
                meta: CacheMeta(source: payload.meta.source),
                accounts: []
            ),
            incoming: payload.accounts,
            systemStateWasRefreshed: false
        )
    }

    private func normalizedAccountIdentity(
        for account: AccountSnapshot
    ) -> AccountSnapshot {
        let identity = AccountIdentity.key(for: account)

        return AccountSnapshot(
            accountId: identity.storageKey,
            label: account.label,
            email: account.email,
            workspaceId: identity.workspaceSlot,
            workspaceLabel: account.workspaceLabel,
            plan: account.plan,
            source: account.source,
            systemAuthProfileId: account.systemAuthProfileId,
            isCurrentSystemAccount: account.isCurrentSystemAccount,
            lastSyncedAt: account.lastSyncedAt,
            usageWindows: account.usageWindows,
            resetCredits: account.resetCredits
        )
    }

    private func preferredAccountSnapshot(
        current: AccountSnapshot?,
        candidate: AccountSnapshot
    ) -> AccountSnapshot {
        guard let current else {
            return candidate
        }

        let currentDate = ISO8601DateFormatter().date(from: current.lastSyncedAt) ?? .distantPast
        let candidateDate = ISO8601DateFormatter().date(from: candidate.lastSyncedAt) ?? .distantPast
        let newest = candidateDate >= currentDate ? candidate : current

        return AccountSnapshot(
            accountId: newest.accountId,
            label: newest.label,
            email: newest.email,
            workspaceId: newest.workspaceId,
            workspaceLabel: newest.workspaceLabel,
            plan: newest.plan,
            source: newest.source,
            systemAuthProfileId: newest.systemAuthProfileId,
            isCurrentSystemAccount: newest.isCurrentSystemAccount,
            lastSyncedAt: newest.lastSyncedAt,
            usageWindows: newest.usageWindows,
            resetCredits: newest.resetCredits
        )
    }
}

final class AccountConfigStore {
    private let durableStore = DurableStoreCoordinator.shared

    func load() -> PulseConfig {
        self.durableStore.loadConfig(
            fallback: .default
        )
    }

    func save(_ config: PulseConfig) throws {
        try self.durableStore.saveConfig(
            config,
            event: "config.save"
        )
    }

    func removeAccount(withID accountID: String) throws {
        let existing = self.load()
        let filteredAccounts = existing.accounts.filter { $0.id != accountID }
        try self.save(
            PulseConfig(
                pollIntervalSeconds: existing.pollIntervalSeconds,
                accounts: filteredAccounts
            )
        )
    }
}

final class DisplayNameStore: ObservableObject {
    @Published private(set) var displayNames: [String: String]

    private let durableStore = DurableStoreCoordinator.shared

    init(displayNames: [String: String]? = nil) {
        self.displayNames = displayNames ?? self.durableStore.loadDisplayNames()
    }

    private func loadDisplayNames() -> [String: String] {
        self.durableStore.loadDisplayNames()
    }

    private func persistDisplayNames(_ displayNames: [String: String]) {
        self.displayNames = displayNames
        try? self.durableStore.saveDisplayNames(
            displayNames,
            event: "display_names.save"
        )
    }

    private func normalizedEmail(for account: AccountSnapshot) -> String {
        AccountIdentity.normalizedEmail(account.email)
    }

    private func resolvedDisplayName(for account: AccountSnapshot) -> String {
        let email = self.normalizedEmail(for: account)
        guard !email.isEmpty else {
            return ""
        }

        return self.displayNames[email]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func displayName(for account: AccountSnapshot) -> String {
        let displayName = self.resolvedDisplayName(for: account)
        return displayName.isEmpty ? account.label : displayName
    }

    func editableDisplayName(for account: AccountSnapshot) -> String {
        self.resolvedDisplayName(for: account)
    }

    func saveDisplayNames(_ values: [String: String], for accounts: [AccountSnapshot]) {
        var nextDisplayNames = self.loadDisplayNames()

        for account in accounts {
            let email = self.normalizedEmail(for: account)
            let trimmed = values[account.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !email.isEmpty else {
                continue
            }

            if !trimmed.isEmpty {
                nextDisplayNames[email] = trimmed
            } else {
                nextDisplayNames.removeValue(forKey: email)
            }
        }

        self.persistDisplayNames(nextDisplayNames)
    }

    func removeDisplayName(for account: AccountSnapshot) {
        var nextDisplayNames = self.loadDisplayNames()
        let email = self.normalizedEmail(for: account)

        if !email.isEmpty {
            nextDisplayNames.removeValue(forKey: email)
        }

        self.persistDisplayNames(nextDisplayNames)
    }
}
