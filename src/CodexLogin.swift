import Foundation
#if canImport(Darwin)
import Darwin
#endif

private let codexLoginTimeout: TimeInterval = 120
private let codexLoginOutputLimit = 1_200

struct CodexLoginRunner {
    struct Result: Equatable {
        enum Outcome: Equatable {
            case success
            case timedOut
            case failed(status: Int32)
            case missingBinary
            case launchFailed(String)
        }

        let outcome: Outcome
        let output: String
    }

    static func run(
        timeout: TimeInterval = codexLoginTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchPaths: [String] = Self.defaultSearchPaths()
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let environment = self.effectiveEnvironment(
                environment,
                additionalSearchPaths: additionalSearchPaths
            )
            guard let executable = self.resolveCodexBinary(environment: environment) else {
                return Result(outcome: .missingBinary, output: "")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["login"]
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            let stdoutCapture = ProcessOutputCapture(pipe: stdout)
            let stderrCapture = ProcessOutputCapture(pipe: stderr)
            process.standardOutput = stdout
            process.standardError = stderr

            stdoutCapture.start()
            stderrCapture.start()

            do {
                try process.run()
            } catch {
                return Result(outcome: .launchFailed(error.localizedDescription), output: "")
            }

            let completed = self.waitUntilExit(process, timeout: timeout)
            if !completed {
                self.terminate(process)
            }

            let output = self.combinedOutput(stdout: stdoutCapture, stderr: stderrCapture)
            if !completed {
                return Result(outcome: .timedOut, output: output)
            }

            let status = process.terminationStatus
            if status == 0 {
                return Result(outcome: .success, output: output)
            }

            return Result(outcome: .failed(status: status), output: output)
        }.value
    }

    private static func effectiveEnvironment(
        _ environment: [String: String],
        additionalSearchPaths: [String]
    ) -> [String: String] {
        var resolved = environment
        resolved["PATH"] = self.expandedPathValue(
            from: environment,
            additionalSearchPaths: additionalSearchPaths
        )
        return resolved
    }

    private static func expandedPathValue(
        from environment: [String: String],
        additionalSearchPaths: [String]
    ) -> String {
        let rawParts = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        return self.uniquePathParts(rawParts + additionalSearchPaths).joined(separator: ":")
    }

    private static func defaultSearchPaths() -> [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    }

    private static func uniquePathParts(_ parts: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueParts: [String] = []

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }

            seen.insert(trimmed)
            uniqueParts.append(trimmed)
        }

        return uniqueParts
    }

    private static func resolveCodexBinary(
        environment: [String: String],
        fileManager: FileManager = .default
    ) -> String? {
        let pathParts = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in self.uniquePathParts(pathParts) {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
                .path

            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func waitUntilExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(max(0, timeout))

        while process.isRunning {
            if Date() >= deadline {
                return false
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        return true
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        process.terminate()

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            #if canImport(Darwin)
            kill(process.processIdentifier, SIGKILL)
            #else
            process.interrupt()
            #endif
        }
    }

    private static func combinedOutput(
        stdout: ProcessOutputCapture,
        stderr: ProcessOutputCapture
    ) -> String {
        let stdoutText = self.decode(stdout.finish())
        let stderrText = self.decode(stderr.finish())

        if !stdoutText.isEmpty, !stderrText.isEmpty {
            return "\(stdoutText)\n\(stderrText)"
        }

        return stdoutText.isEmpty ? stderrText : stdoutText
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

@MainActor
final class CodexLoginStore: ObservableObject {
    @Published private(set) var isAddingAccount = false
    @Published var errorMessage: String?

    func addAccount() async -> Bool {
        guard !self.isAddingAccount else {
            return false
        }

        self.isAddingAccount = true
        defer {
            self.isAddingAccount = false
        }

        let result = await CodexLoginRunner.run()
        switch result.outcome {
        case .success:
            self.errorMessage = nil
            return true
        case .missingBinary:
            self.errorMessage = "Comux could not find the Codex CLI. Install Codex CLI and make sure `codex` is available on PATH, then try again."
        case .timedOut:
            self.errorMessage = Self.message(
                "codex login did not finish within two minutes. Complete the login in your browser, then try again.",
                output: result.output
            )
        case .failed(let status):
            self.errorMessage = Self.message(
                "codex login exited with status \(status).",
                output: result.output
            )
        case .launchFailed(let details):
            self.errorMessage = "Comux could not start codex login. \(details)"
        }

        return false
    }

    func clearError() {
        self.errorMessage = nil
    }

    private static func message(_ base: String, output: String) -> String {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            return base
        }

        return "\(base)\n\ncodex login output:\n\(self.truncated(trimmedOutput))"
    }

    private static func truncated(_ output: String) -> String {
        guard output.count > codexLoginOutputLimit else {
            return output
        }

        let prefix = output.prefix(codexLoginOutputLimit)
        return "\(prefix)\n..."
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(pipe: Pipe) {
        self.handle = pipe.fileHandleForReading
    }

    func start() {
        self.handle.readabilityHandler = { [weak self] handle in
            guard let self else {
                return
            }

            let availableData = handle.availableData
            guard !availableData.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            self.append(availableData)
        }
    }

    func finish() -> Data {
        self.handle.readabilityHandler = nil
        let remainingData = self.handle.readDataToEndOfFile()
        self.append(remainingData)

        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.data
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        self.lock.lock()
        self.data.append(chunk)
        self.lock.unlock()
    }
}
