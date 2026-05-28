import Foundation

struct AccountSnapshotMerger {
    func merge(
        existing: CachePayload,
        incoming: [AccountSnapshot],
        systemStateWasRefreshed: Bool = false
    ) -> CachePayload {
        var existingByIdentity: [String: AccountSnapshot] = [:]

        for account in existing.accounts {
            let prior = existingByIdentity[account.accountId]
            existingByIdentity[account.accountId] = self.preferredStoredSnapshot(prior, candidate: account)
        }

        var activeIdentity: String?

        for snapshot in incoming {
            let mergedSnapshot = self.mergedIncomingSnapshot(
                snapshot,
                existingSnapshots: Array(existingByIdentity.values)
            )
            existingByIdentity[mergedSnapshot.accountId] = mergedSnapshot

            if mergedSnapshot.isCurrentSystemAccount == true {
                activeIdentity = mergedSnapshot.accountId
            }
        }

        var mergedAccounts = self.collapsedBrokenSystemSnapshots(
            in: Array(existingByIdentity.values)
        )

        if let activeIdentity {
            mergedAccounts = mergedAccounts.map { account in
                self.snapshot(
                    from: account,
                    isCurrentSystemAccount: account.accountId == activeIdentity
                )
            }
        } else if systemStateWasRefreshed {
            mergedAccounts = mergedAccounts.map { account in
                self.snapshot(
                    from: account,
                    isCurrentSystemAccount: false
                )
            }
        }

        mergedAccounts.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        return CachePayload(
            meta: CacheMeta(
                source: "native-swift-cache"
            ),
            accounts: mergedAccounts
        )
    }

    private func mergedIncomingSnapshot(
        _ incoming: AccountSnapshot,
        existingSnapshots: [AccountSnapshot]
    ) -> AccountSnapshot {
        guard let existing = self.cachedSeatSnapshot(
            for: incoming,
            in: existingSnapshots
        ) else {
            return incoming
        }

        let shouldPreserveSeatMetadata = self.shouldPreserveCachedSeatMetadata(
            existing: existing,
            incoming: incoming
        )

        return AccountSnapshot(
            accountId: shouldPreserveSeatMetadata ? existing.accountId : incoming.accountId,
            label: incoming.label,
            email: incoming.email,
            workspaceId: shouldPreserveSeatMetadata ? existing.workspaceId : incoming.workspaceId,
            workspaceLabel: shouldPreserveSeatMetadata ? existing.workspaceLabel : incoming.workspaceLabel,
            plan: shouldPreserveSeatMetadata ? existing.plan : incoming.plan,
            source: incoming.source,
            systemAuthProfileId: incoming.systemAuthProfileId ?? existing.systemAuthProfileId,
            isCurrentSystemAccount: incoming.isCurrentSystemAccount,
            lastSyncedAt: incoming.lastSyncedAt,
            weeklyWindow: self.preferredUsageWindow(
                current: existing.weeklyWindow,
                candidate: incoming.weeklyWindow
            ),
            rollingWindow: self.preferredUsageWindow(
                current: existing.rollingWindow,
                candidate: incoming.rollingWindow
            )
        )
    }

    private func preferredStoredSnapshot(
        _ current: AccountSnapshot?,
        candidate: AccountSnapshot
    ) -> AccountSnapshot {
        guard let current else {
            return candidate
        }

        let currentDate = ISO8601DateFormatter().date(from: current.lastSyncedAt) ?? .distantPast
        let candidateDate = ISO8601DateFormatter().date(from: candidate.lastSyncedAt) ?? .distantPast
        let newest = candidateDate >= currentDate ? candidate : current

        return self.snapshot(
            from: newest,
            isCurrentSystemAccount: newest.isCurrentSystemAccount
        )
    }

    private func cachedSeatSnapshot(
        for incoming: AccountSnapshot,
        in existingSnapshots: [AccountSnapshot]
    ) -> AccountSnapshot? {
        guard incoming.source == "live system auth" else {
            return existingSnapshots.first(where: { $0.accountId == incoming.accountId })
        }

        let exactMatch = existingSnapshots.first(where: { $0.accountId == incoming.accountId })
        let incomingProfileID = normalizedSystemAuthProfileID(incoming.systemAuthProfileId)
        let sameProfileSnapshots = existingSnapshots.filter {
            $0.source == "live system auth"
                && normalizedSystemAuthProfileID($0.systemAuthProfileId) == incomingProfileID
        }

        if !self.isBrokenSeatFallbackSnapshot(incoming) {
            return exactMatch
        }

        let workspaceBackedCandidate = sameProfileSnapshots
            .filter { self.shouldPreserveCachedSeatMetadata(existing: $0, incoming: incoming) }
            .max { left, right in
                self.snapshotRecency(left) < self.snapshotRecency(right)
            }

        return workspaceBackedCandidate ?? exactMatch
    }

    private func shouldPreserveCachedSeatMetadata(
        existing: AccountSnapshot,
        incoming: AccountSnapshot
    ) -> Bool {
        guard existing.source == "live system auth",
              incoming.source == "live system auth"
        else {
            return false
        }

        let existingWorkspace = normalizedWorkspaceLabel(
            existing.workspaceLabel,
            plan: existing.plan
        )
        let incomingWorkspace = normalizedWorkspaceLabel(
            incoming.workspaceLabel,
            plan: incoming.plan
        )
        let existingWorkspaceID = AccountIdentity.resolvedWorkspaceID(
            accountId: existing.accountId,
            workspaceId: existing.workspaceId
        )
        let incomingWorkspaceID = AccountIdentity.resolvedWorkspaceID(
            accountId: incoming.accountId,
            workspaceId: incoming.workspaceId
        )

        guard existingWorkspaceID != nil,
              !existingWorkspace.isEmpty,
              existingWorkspace != "Personal"
        else {
            return false
        }

        return incomingWorkspaceID == nil
            || incomingWorkspace.isEmpty
            || incomingWorkspace == "Personal"
            || !incoming.weeklyWindow.available
    }

    private func preferredUsageWindow(
        current: UsageWindow,
        candidate: UsageWindow
    ) -> UsageWindow {
        candidate.available ? candidate : current
    }

    private func isBrokenSeatFallbackSnapshot(_ account: AccountSnapshot) -> Bool {
        guard account.source == "live system auth" else {
            return false
        }

        let workspaceID = AccountIdentity.resolvedWorkspaceID(
            accountId: account.accountId,
            workspaceId: account.workspaceId
        )
        let workspace = normalizedWorkspaceLabel(
            account.workspaceLabel,
            plan: account.plan
        )

        return workspaceID == nil
            && workspace == "Personal"
            && !account.weeklyWindow.available
    }

    private func collapsedBrokenSystemSnapshots(
        in accounts: [AccountSnapshot]
    ) -> [AccountSnapshot] {
        accounts.filter { candidate in
            guard self.isBrokenSeatFallbackSnapshot(candidate),
                  let candidateProfileID = normalizedSystemAuthProfileID(candidate.systemAuthProfileId)
            else {
                return true
            }

            return !accounts.contains { peer in
                guard peer.accountId != candidate.accountId,
                      peer.source == "live system auth",
                      normalizedSystemAuthProfileID(peer.systemAuthProfileId) == candidateProfileID
                else {
                    return false
                }

                return self.shouldPreserveCachedSeatMetadata(
                    existing: peer,
                    incoming: candidate
                )
            }
        }
    }

    private func snapshotRecency(_ account: AccountSnapshot) -> Date {
        ISO8601DateFormatter().date(from: account.lastSyncedAt) ?? .distantPast
    }

    private func shouldDiscardSupersededSystemSnapshot(
        _ existing: AccountSnapshot,
        incoming: [AccountSnapshot]
    ) -> Bool {
        guard existing.source == "live system auth",
              let existingProfileID = normalizedSystemAuthProfileID(existing.systemAuthProfileId)
        else {
            return false
        }

        let incomingForProfile = incoming.filter {
            $0.source == "live system auth"
                && normalizedSystemAuthProfileID($0.systemAuthProfileId) == existingProfileID
        }

        guard !incomingForProfile.isEmpty else {
            return false
        }

        let existingWorkspaceSlot = self.systemWorkspaceSlot(for: existing)
        guard existingWorkspaceSlot != nil else {
            return false
        }

        return incomingForProfile.contains { candidate in
            candidate.accountId != existing.accountId
                && self.systemWorkspaceSlot(for: candidate) == existingWorkspaceSlot
        }
    }

    private func systemWorkspaceSlot(for account: AccountSnapshot) -> String? {
        AccountIdentity.key(for: account).workspaceSlot
    }

    private func snapshot(
        from account: AccountSnapshot,
        isCurrentSystemAccount: Bool?
    ) -> AccountSnapshot {
        AccountSnapshot(
            accountId: account.accountId,
            label: account.label,
            email: account.email,
            workspaceId: account.workspaceId,
            workspaceLabel: account.workspaceLabel,
            plan: account.plan,
            source: account.source,
            systemAuthProfileId: account.systemAuthProfileId,
            isCurrentSystemAccount: isCurrentSystemAccount,
            lastSyncedAt: account.lastSyncedAt,
            weeklyWindow: account.weeklyWindow,
            rollingWindow: account.rollingWindow
        )
    }
}
