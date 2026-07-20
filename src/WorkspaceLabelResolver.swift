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

    static func workspaceListRequest(
        accessToken: String,
        cookieHeader: String?,
        accountHeader: String?
    ) -> URLRequest {
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/accounts")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if let accountHeader, !accountHeader.isEmpty {
            request.setValue(accountHeader, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        return request
    }
}
