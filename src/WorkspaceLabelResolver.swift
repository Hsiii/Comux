import Foundation

enum WorkspaceLabelResolver {
    static func resolve(
        workspaceItems: [WorkspaceItem],
        workspaceAccountID: String?,
        normalizeWorkspaceAccountID: (String?) -> String?
    ) -> String? {
        guard let normalizedWorkspaceAccountID = normalizeWorkspaceAccountID(workspaceAccountID) else {
            return nil
        }

        let matchingWorkspace = workspaceItems.first { item in
            normalizeWorkspaceAccountID(item.id) == normalizedWorkspaceAccountID
        }

        return matchingWorkspace?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
