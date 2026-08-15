import Foundation

struct CodexRateLimitsSnapshot: Equatable {
    let usageWindows: [UsageWindow]
    let resetCredits: CodexResetCredits?
}

enum CodexAppServerRateLimitsParser {
    static func parse(
        _ payload: [String: Any],
        now: Date = Date()
    ) -> CodexRateLimitsSnapshot? {
        guard let result = payload["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any]
        else {
            return nil
        }

        let usageWindows = [
            Self.window(id: "app-server-primary", payload: rateLimits["primary"]),
            Self.window(id: "app-server-secondary", payload: rateLimits["secondary"]),
        ].compactMap { $0 }

        return CodexRateLimitsSnapshot(
            usageWindows: usageWindows,
            resetCredits: Self.resetCredits(
                from: result["rateLimitResetCredits"],
                now: now
            )
        )
    }

    private static func window(
        id: String,
        payload: Any?
    ) -> UsageWindow? {
        guard let payload = payload as? [String: Any],
              let durationMinutes = (payload["windowDurationMins"] as? NSNumber)?.intValue,
              durationMinutes > 0
        else {
            return nil
        }

        return UsageWindowFactory.make(
            id: id,
            durationSeconds: durationMinutes * 60,
            usedPercent: (payload["usedPercent"] as? NSNumber)?.doubleValue ?? 0,
            resetsAtEpoch: (payload["resetsAt"] as? NSNumber)?.doubleValue
        )
    }

    private static func resetCredits(
        from payload: Any?,
        now: Date
    ) -> CodexResetCredits? {
        guard let payload = payload as? [String: Any] else {
            return nil
        }

        let rawCredits = payload["credits"] as? [[String: Any]] ?? []
        let availableCredits = rawCredits.filter { credit in
            (credit["status"] as? String) == "available"
        }
        let availableCount = (payload["availableCount"] as? NSNumber)
            .map { max($0.intValue, 0) }
            ?? availableCredits.count
        let nextExpiry = availableCredits.compactMap { credit -> Date? in
            guard let epoch = (credit["expiresAt"] as? NSNumber)?.doubleValue,
                  epoch > 0
            else {
                return nil
            }

            let expiry = Date(timeIntervalSince1970: epoch)
            return expiry > now ? expiry : nil
        }.min()

        return CodexResetCredits(
            availableCount: availableCount,
            nextExpiresAt: nextExpiry?.ISO8601Format(),
            updatedAt: now.ISO8601Format()
        )
    }
}

enum CodexAppServerExecutable {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        for candidate in Self.candidates(environment: environment) {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func candidates(environment: [String: String]) -> [String] {
        let home = NSHomeDirectory()
        let bundledCandidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
        ]
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { directory in
                URL(fileURLWithPath: String(directory), isDirectory: true)
                    .appendingPathComponent("codex", isDirectory: false)
                    .path
            }

        var seen = Set<String>()
        return (bundledCandidates + pathCandidates).filter { seen.insert($0).inserted }
    }
}

enum CodexAppServerRateLimitsReader {
    static func read(
        timeout: TimeInterval = 5,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> CodexRateLimitsSnapshot? {
        guard let executable = CodexAppServerExecutable.resolve(environment: environment) else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            Self.read(
                executable: executable,
                timeout: timeout,
                environment: environment
            )
        }.value
    }

    static func read(
        executable: String,
        timeout: TimeInterval,
        environment: [String: String]
    ) -> CodexRateLimitsSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.environment = environment

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let responseCapture = CodexAppServerResponseCapture(
            input: standardInput.fileHandleForWriting
        )

        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        responseCapture.start(reading: standardOutput.fileHandleForReading)
        standardError.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
            try responseCapture.send([
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "comux",
                        "title": "Comux",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
                    ],
                ],
            ])
        } catch {
            responseCapture.stop()
            standardError.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let snapshot = responseCapture.wait(timeout: max(timeout, 0))
        responseCapture.stop()
        standardError.fileHandleForReading.readabilityHandler = nil
        try? standardInput.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()
        }

        return snapshot
    }
}

final class CodexAppServerResponseCapture: @unchecked Sendable {
    private let input: FileHandle
    private let lock = NSLock()
    private let completion = DispatchSemaphore(value: 0)
    private var output: FileHandle?
    private var buffer = Data()
    private var didRequestRateLimits = false
    private var didComplete = false
    private var snapshot: CodexRateLimitsSnapshot?

    init(input: FileHandle) {
        self.input = input
    }

    func start(reading output: FileHandle) {
        self.lock.lock()
        self.output = output
        self.lock.unlock()

        output.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                self?.stop()
                return
            }

            self?.receive(data)
        }
    }

    func stop() {
        self.lock.lock()
        let shouldSignal = !self.didComplete
        self.didComplete = true
        let output = self.output
        self.output = nil
        self.lock.unlock()

        output?.readabilityHandler = nil

        if shouldSignal {
            self.completion.signal()
        }
    }

    func send(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try self.input.write(contentsOf: data + Data([0x0A]))
    }

    func wait(timeout: TimeInterval) -> CodexRateLimitsSnapshot? {
        _ = self.completion.wait(timeout: .now() + timeout)

        self.lock.lock()
        defer { self.lock.unlock() }
        return self.snapshot
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else {
            self.stop()
            return
        }

        self.lock.lock()
        self.buffer.append(data)
        let messages = self.drainMessagesLocked()
        self.lock.unlock()

        for message in messages {
            self.handle(message)
        }
    }

    private func drainMessagesLocked() -> [[String: Any]] {
        var messages: [[String: Any]] = []

        while let newline = self.buffer.firstIndex(of: 0x0A) {
            let line = self.buffer[..<newline]
            self.buffer.removeSubrange(...newline)

            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else {
                continue
            }

            messages.append(message)
        }

        return messages
    }

    private func handle(_ message: [String: Any]) {
        let responseID = (message["id"] as? NSNumber)?.intValue

        if responseID == 1 {
            self.lock.lock()
            let shouldRequest = !self.didRequestRateLimits && !self.didComplete
            self.didRequestRateLimits = true
            self.lock.unlock()

            guard shouldRequest else {
                return
            }

            try? self.send(["method": "initialized", "params": [:]])
            try? self.send(["method": "account/rateLimits/read", "id": 2])
            return
        }

        guard responseID == 2 else {
            return
        }

        let snapshot = CodexAppServerRateLimitsParser.parse(message)

        self.lock.lock()
        guard !self.didComplete else {
            self.lock.unlock()
            return
        }
        self.snapshot = snapshot
        self.didComplete = true
        self.lock.unlock()
        self.completion.signal()
    }
}
