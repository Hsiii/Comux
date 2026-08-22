import Foundation
#if canImport(Darwin)
import Darwin
#endif

private let resetCountdownTimeout: TimeInterval = 60
private let resetCountdownOutputLimit = 1_200

struct ResetCountdownRunner {
    struct Result: Equatable, Sendable {
        enum Outcome: Equatable, Sendable {
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
        timeout: TimeInterval = resetCountdownTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Result {
        guard let executable = CodexAppServerExecutable.resolve(environment: environment) else {
            return Result(outcome: .missingBinary, output: "")
        }

        return await self.run(
            executable: executable,
            timeout: timeout,
            environment: environment
        )
    }

    static func run(
        executable: String,
        timeout: TimeInterval,
        environment: [String: String]
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [
                "exec",
                "--model", "gpt-5.6-luna",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--cd", FileManager.default.temporaryDirectory.path,
                "Reply with exactly hi. Do not use tools or inspect files.",
            ]
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
            guard completed else {
                return Result(outcome: .timedOut, output: output)
            }

            let status = process.terminationStatus
            return Result(
                outcome: status == 0 ? .success : .failed(status: status),
                output: output
            )
        }.value
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
        let output: String

        if !stdoutText.isEmpty, !stderrText.isEmpty {
            output = "\(stdoutText)\n\(stderrText)"
        } else {
            output = stdoutText.isEmpty ? stderrText : stdoutText
        }

        guard output.count > resetCountdownOutputLimit else {
            return output
        }

        return "\(output.prefix(resetCountdownOutputLimit))\n..."
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }
}
