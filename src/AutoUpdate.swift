import AppKit
import CryptoKit
import Foundation

struct AutoUpdateVersion: Comparable, Equatable, Sendable {
    let rawValue: String
    let normalized: String
    private let coreIdentifiers: [Int]
    private let prereleaseIdentifiers: [String]

    init(_ rawValue: String) {
        self.rawValue = rawValue

        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
        let releaseAndBuild = trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let release = String(releaseAndBuild.first ?? "")
        self.normalized = release

        let releaseParts = release.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = releaseParts.first.map(String.init) ?? ""
        self.coreIdentifiers = core
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        self.prereleaseIdentifiers = releaseParts.count > 1
            ? releaseParts[1].split(separator: ".").map(String.init)
            : []
    }

    static func == (lhs: AutoUpdateVersion, rhs: AutoUpdateVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: AutoUpdateVersion, rhs: AutoUpdateVersion) -> Bool {
        let coreCount = max(lhs.coreIdentifiers.count, rhs.coreIdentifiers.count)
        for index in 0..<coreCount {
            let left = lhs.coreIdentifiers[safe: index] ?? 0
            let right = rhs.coreIdentifiers[safe: index] ?? 0
            if left != right {
                return left < right
            }
        }

        if lhs.prereleaseIdentifiers.isEmpty || rhs.prereleaseIdentifiers.isEmpty {
            return !lhs.prereleaseIdentifiers.isEmpty && rhs.prereleaseIdentifiers.isEmpty
        }

        let prereleaseCount = max(lhs.prereleaseIdentifiers.count, rhs.prereleaseIdentifiers.count)
        for index in 0..<prereleaseCount {
            guard let left = lhs.prereleaseIdentifiers[safe: index] else {
                return true
            }
            guard let right = rhs.prereleaseIdentifiers[safe: index] else {
                return false
            }

            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case (.some(let leftNumber), .some(let rightNumber)):
                if leftNumber != rightNumber {
                    return leftNumber < rightNumber
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                if left != right {
                    return left < right
                }
            }
        }

        return false
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else {
            return self
        }

        return String(self.dropFirst(prefix.count))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard self.indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}

struct AutoUpdateCandidate: Equatable, Sendable {
    let version: String
    let pageURL: URL
    let archiveURL: URL
    let expectedSHA256: String
}

struct StagedAutoUpdate: Sendable {
    let appURL: URL
    let stagingDirectory: URL
}

enum AutoUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable(AutoUpdateCandidate)
    case downloading(AutoUpdateCandidate)
    case installing(AutoUpdateCandidate)
}

extension AutoUpdateStatus {
    var menuTitle: String {
        switch self {
        case .idle, .upToDate:
            return "Latest Version Installed"
        case .checking:
            return "Checking for Updates..."
        case .updateAvailable:
            return "Update Available"
        case .downloading:
            return "Downloading Update..."
        case .installing:
            return "Installing Update..."
        }
    }

    var isMenuRowDimmed: Bool {
        if case .updateAvailable = self {
            return false
        }

        return true
    }
}

enum AutoUpdateError: LocalizedError, Sendable {
    case latestReleaseUnavailable(Int)
    case releaseArchiveMissing(String)
    case releaseChecksumMissing
    case checksumMismatch(expected: String, actual: String)
    case extractedAppMissing
    case invalidBundleIdentifier(String?)
    case invalidBundleVersion(expected: String, actual: String?)
    case commandFailed(String)
    case currentAppBundleUnavailable
    case installLocationNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .latestReleaseUnavailable(let statusCode):
            return "GitHub rejected the update request with HTTP \(statusCode)."
        case .releaseArchiveMissing(let version):
            return "The latest GitHub release does not include the comux-\(version).zip archive."
        case .releaseChecksumMissing:
            return "The latest GitHub release does not include a Homebrew checksum for the update archive."
        case .checksumMismatch:
            return "The downloaded update did not match the published checksum."
        case .extractedAppMissing:
            return "The downloaded update archive did not contain comux.app."
        case .invalidBundleIdentifier:
            return "The downloaded update is not a Comux app bundle."
        case .invalidBundleVersion(let expected, let actual):
            let actualDescription = actual ?? "missing"
            return "The downloaded app version was \(actualDescription), but Comux expected \(expected)."
        case .commandFailed(let message):
            return message
        case .currentAppBundleUnavailable:
            return "Automatic installation only works when Comux is running from the app bundle. Install Comux in /Applications and try again."
        case .installLocationNotWritable(let path):
            return "Comux cannot replace the app at \(path). Check the app permissions or install the update manually."
        }
    }
}

enum AutoUpdateCaskParser {
    static func extractSHA256(from cask: String) -> String? {
        for line in cask.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("sha256 ") else {
                continue
            }

            let value = trimmed
                .dropFirst("sha256 ".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if value.hasPrefix("\""), value.hasSuffix("\"") {
                return String(value.dropFirst().dropLast()).lowercased()
            }

            return value.lowercased()
        }

        return nil
    }
}

actor GitHubReleaseUpdateClient {
    private static let bundleIdentifier = "dev.hsi.comux.app"
    private static let appBundleName = "comux.app"

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/Hsiii/Comux/releases/latest")!
    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func fetchAvailableUpdate(currentVersion: String) async throws -> AutoUpdateCandidate? {
        let (data, response) = try await self.session.data(for: self.request(for: self.latestReleaseURL))
        try Self.validateHTTPResponse(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubReleaseResponse.self, from: data)
        let latestVersion = AutoUpdateVersion(release.tagName)

        guard latestVersion > AutoUpdateVersion(currentVersion) else {
            return nil
        }

        let archiveName = "comux-\(latestVersion.normalized).zip"
        guard let archive = release.assets.first(where: { $0.name == archiveName }) else {
            throw AutoUpdateError.releaseArchiveMissing(latestVersion.normalized)
        }
        guard let cask = release.assets.first(where: { $0.name == "comux.rb" }) else {
            throw AutoUpdateError.releaseChecksumMissing
        }

        let (caskData, caskResponse) = try await self.session.data(for: self.request(for: cask.browserDownloadUrl))
        try Self.validateHTTPResponse(caskResponse)

        guard
            let caskBody = String(data: caskData, encoding: .utf8),
            let checksum = AutoUpdateCaskParser.extractSHA256(from: caskBody)
        else {
            throw AutoUpdateError.releaseChecksumMissing
        }

        return AutoUpdateCandidate(
            version: latestVersion.normalized,
            pageURL: release.htmlUrl,
            archiveURL: archive.browserDownloadUrl,
            expectedSHA256: checksum
        )
    }

    func downloadAndStageUpdate(_ candidate: AutoUpdateCandidate) async throws -> StagedAutoUpdate {
        let stagingDirectory = self.fileManager
            .temporaryDirectory
            .appendingPathComponent("comux-update-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = stagingDirectory.appendingPathComponent("comux-\(candidate.version).zip", isDirectory: false)
        let extractionDirectory = stagingDirectory.appendingPathComponent("extracted", isDirectory: true)

        try self.fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            let (downloadURL, response) = try await self.session.download(for: self.request(for: candidate.archiveURL))
            try Self.validateHTTPResponse(response)
            try self.fileManager.moveItem(at: downloadURL, to: archiveURL)

            let actualChecksum = try Self.sha256Hex(for: archiveURL)
            guard actualChecksum == candidate.expectedSHA256.lowercased() else {
                throw AutoUpdateError.checksumMismatch(expected: candidate.expectedSHA256, actual: actualChecksum)
            }

            try self.fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
            try Self.runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path])

            let appURL = extractionDirectory.appendingPathComponent(Self.appBundleName, isDirectory: true)
            try Self.validateExtractedApp(at: appURL, expectedVersion: candidate.version)
            return StagedAutoUpdate(appURL: appURL, stagingDirectory: stagingDirectory)
        } catch {
            try? self.fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    func scheduleReplacement(with stagedUpdate: StagedAutoUpdate) throws {
        let currentAppURL = Bundle.main.bundleURL
        guard currentAppURL.pathExtension == "app" else {
            throw AutoUpdateError.currentAppBundleUnavailable
        }

        try self.verifyInstallLocation(for: currentAppURL)

        let scriptURL = stagedUpdate.stagingDirectory.appendingPathComponent("install-comux-update.sh", isDirectory: false)
        let script = Self.replacementScript(
            currentAppURL: currentAppURL,
            newAppURL: stagedUpdate.appURL,
            stagingDirectory: stagedUpdate.stagingDirectory,
            currentProcessID: ProcessInfo.processInfo.processIdentifier
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try self.fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Comux/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func verifyInstallLocation(for appURL: URL) throws {
        let parent = appURL.deletingLastPathComponent()
        guard self.fileManager.isWritableFile(atPath: parent.path) else {
            throw AutoUpdateError.installLocationNotWritable(appURL.path)
        }

        let probeURL = parent.appendingPathComponent(".comux-update-\(UUID().uuidString)", isDirectory: false)
        do {
            try Data().write(to: probeURL, options: .withoutOverwriting)
            try self.fileManager.removeItem(at: probeURL)
        } catch {
            throw AutoUpdateError.installLocationNotWritable(appURL.path)
        }
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AutoUpdateError.latestReleaseUnavailable(httpResponse.statusCode)
        }
    }

    private static func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func validateExtractedApp(at appURL: URL, expectedVersion: String) throws {
        guard fileExists(at: appURL), let bundle = Bundle(url: appURL) else {
            throw AutoUpdateError.extractedAppMissing
        }

        guard bundle.bundleIdentifier == Self.bundleIdentifier else {
            throw AutoUpdateError.invalidBundleIdentifier(bundle.bundleIdentifier)
        }

        let actualVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard actualVersion == expectedVersion else {
            throw AutoUpdateError.invalidBundleVersion(expected: expectedVersion, actual: actualVersion)
        }

        try selfCheckCodeSignature(at: appURL)
    }

    private static func fileExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func selfCheckCodeSignature(at appURL: URL) throws {
        do {
            try Self.runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
        } catch let error as AutoUpdateError {
            throw error
        } catch {
            throw AutoUpdateError.commandFailed("The downloaded update could not be verified.")
        }
    }

    private static func runProcess(_ executablePath: String, arguments: [String]) throws {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let commandName = URL(fileURLWithPath: executablePath).lastPathComponent
            let details = output?.isEmpty == false ? ": \(output!)" : ""
            throw AutoUpdateError.commandFailed("\(commandName) failed\(details)")
        }
    }

    private static func replacementScript(
        currentAppURL: URL,
        newAppURL: URL,
        stagingDirectory: URL,
        currentProcessID: Int32
    ) -> String {
        let currentApp = Self.shellQuoted(currentAppURL.path)
        let newApp = Self.shellQuoted(newAppURL.path)
        let staging = Self.shellQuoted(stagingDirectory.path)

        return """
        #!/bin/zsh
        set -euo pipefail

        app_path=\(currentApp)
        new_app_path=\(newApp)
        staging_dir=\(staging)
        old_pid=\(currentProcessID)
        backup_path="${app_path}.previous-comux-update"

        for _ in {1..120}; do
            if ! /bin/kill -0 "$old_pid" >/dev/null 2>&1; then
                break
            fi
            /bin/sleep 0.25
        done

        /bin/rm -rf "$backup_path"
        if [[ -d "$app_path" ]]; then
            /bin/mv "$app_path" "$backup_path"
        fi

        if /usr/bin/ditto "$new_app_path" "$app_path"; then
            /usr/bin/xattr -dr com.apple.quarantine "$app_path" >/dev/null 2>&1 || true
            /bin/rm -rf "$backup_path"
            /usr/bin/open "$app_path"
            /bin/rm -rf "$staging_dir"
            exit 0
        fi

        /bin/rm -rf "$app_path"
        if [[ -d "$backup_path" ]]; then
            /bin/mv "$backup_path" "$app_path"
            /usr/bin/open "$app_path" >/dev/null 2>&1 || true
        fi
        exit 1
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private struct GitHubReleaseResponse: Decodable {
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
    }
}

@MainActor
final class AutoUpdateStore: ObservableObject {
    @Published private(set) var status: AutoUpdateStatus = .idle
    @Published var errorMessage: String?

    private static let lastCheckKey = "dev.hsi.comux.lastAutoUpdateCheck"
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let automaticCheckPollingIntervalNanoseconds: UInt64 = 60 * 60 * 1_000_000_000

    private let client: GitHubReleaseUpdateClient
    private let defaults: UserDefaults
    private var automaticCheckTask: Task<Void, Never>?
    private var resetStatusTask: Task<Void, Never>?

    init(
        client: GitHubReleaseUpdateClient = GitHubReleaseUpdateClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
    }

    deinit {
        self.automaticCheckTask?.cancel()
        self.resetStatusTask?.cancel()
    }

    var menuTitle: String {
        self.status.menuTitle
    }

    var isMenuRowDimmed: Bool {
        self.status.isMenuRowDimmed
    }

    var canActivatePrimaryAction: Bool {
        switch self.status {
        case .checking, .downloading, .installing:
            return false
        case .idle, .upToDate, .updateAvailable:
            return true
        }
    }

    func startAutomaticChecks() {
        guard self.automaticCheckTask == nil else {
            return
        }

        self.automaticCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else {
                    return
                }

                if self?.shouldRunAutomaticCheck == true {
                    await self?.checkForUpdates(isUserInitiated: false)
                }

                do {
                    try await Task.sleep(nanoseconds: Self.automaticCheckPollingIntervalNanoseconds)
                } catch {
                    return
                }
            }
        }
    }

    func activatePrimaryAction() async {
        switch self.status {
        case .updateAvailable:
            await self.installAvailableUpdate()
        case .idle, .upToDate:
            await self.checkForUpdates(isUserInitiated: true)
        case .checking, .downloading, .installing:
            break
        }
    }

    func checkForUpdates(isUserInitiated: Bool) async {
        guard self.canStartCheck else {
            return
        }

        self.resetStatusTask?.cancel()
        self.status = .checking

        do {
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let candidate = try await self.client.fetchAvailableUpdate(currentVersion: currentVersion)
            self.defaults.set(Date(), forKey: Self.lastCheckKey)

            if let candidate {
                self.status = .updateAvailable(candidate)
            } else if isUserInitiated {
                self.status = .upToDate
                self.scheduleIdleReset()
            } else {
                self.status = .idle
            }
            self.errorMessage = nil
        } catch {
            self.status = .idle
            if isUserInitiated {
                self.errorMessage = Self.message(for: error)
            }
        }
    }

    func installAvailableUpdate() async {
        guard case .updateAvailable(let candidate) = self.status else {
            await self.checkForUpdates(isUserInitiated: true)
            return
        }

        var stagedUpdate: StagedAutoUpdate?
        self.status = .downloading(candidate)

        do {
            let staged = try await self.client.downloadAndStageUpdate(candidate)
            stagedUpdate = staged
            self.status = .installing(candidate)
            try await self.client.scheduleReplacement(with: staged)
            NSApp.terminate(nil)
        } catch {
            if let stagedUpdate {
                try? FileManager.default.removeItem(at: stagedUpdate.stagingDirectory)
            }

            self.status = .updateAvailable(candidate)
            self.errorMessage = Self.message(for: error)
        }
    }

    func clearError() {
        self.errorMessage = nil
    }

    private var shouldRunAutomaticCheck: Bool {
        guard let lastCheck = self.defaults.object(forKey: Self.lastCheckKey) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastCheck) >= Self.automaticCheckInterval
    }

    private var canStartCheck: Bool {
        switch self.status {
        case .checking, .downloading, .installing:
            return false
        case .idle, .upToDate, .updateAvailable:
            return true
        }
    }

    private func scheduleIdleReset() {
        self.resetStatusTask?.cancel()
        self.resetStatusTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                if self.status == .upToDate {
                    self.status = .idle
                }
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            return "Comux could not complete the update."
        }

        return description
    }
}
