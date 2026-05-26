import Foundation

struct NicknamePayload: Codable {
    let schemaVersion: Int
    let updatedAt: String
    let nicknames: [String: String]

    static let empty = NicknamePayload(
        schemaVersion: 1,
        updatedAt: ISO8601DateFormatter().string(from: .distantPast),
        nicknames: [:]
    )
}

struct StorageLogEntry: Codable {
    let id: String
    let event: String
    let status: String
    let committedAt: String
    let touchedPaths: [String]
}

private struct PendingWrite: Codable {
    let path: String
    let base64Data: String
}

private struct PendingTransaction: Codable {
    let id: String
    let event: String
    let startedAt: String
    let writes: [PendingWrite]
}

private struct EncodedWrite {
    let url: URL
    let data: Data
}

final class DurableStoreCoordinator: @unchecked Sendable {
    static let shared = DurableStoreCoordinator()

    private let queue = DispatchQueue(label: "com.codexmux.storage", qos: .userInitiated)
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    private init() {}

    func load<T: Decodable>(
        from url: URL,
        fallback: @autoclosure () -> T
    ) -> T {
        self.queue.sync {
            try? self.ensureRootDirectoryLocked()
            try? self.recoverPendingTransactionIfNeededLocked()

            guard let data = try? Data(contentsOf: url),
                  let value = try? self.decoder.decode(T.self, from: data) else {
                return fallback()
            }

            return value
        }
    }

    func save<T: Encodable>(
        _ value: T,
        to url: URL,
        event: String
    ) throws {
        let write = try self.encodedWrite(value, to: url)
        try self.commit(writes: [write], event: event)
    }

    func saveCacheAndConfig(
        cache: CachePayload,
        config: PulseConfig,
        event: String
    ) throws {
        let cacheWrite = try self.encodedWrite(cache, to: CodexMuxPaths.cache)
        let configWrite = try self.encodedWrite(config, to: CodexMuxPaths.config)
        try self.commit(writes: [cacheWrite, configWrite], event: event)
    }

    private func encodedWrite<T: Encodable>(
        _ value: T,
        to url: URL
    ) throws -> EncodedWrite {
        EncodedWrite(url: url, data: try self.encoder.encode(value))
    }

    private func commit(
        writes: [EncodedWrite],
        event: String
    ) throws {
        try self.queue.sync {
            try self.ensureRootDirectoryLocked()
            try self.recoverPendingTransactionIfNeededLocked()

            let transaction = PendingTransaction(
                id: UUID().uuidString,
                event: event,
                startedAt: ISO8601DateFormatter().string(from: Date()),
                writes: writes.map { write in
                    PendingWrite(
                        path: write.url.path(percentEncoded: false),
                        base64Data: write.data.base64EncodedString()
                    )
                }
            )

            try self.writeAtomicallyLocked(
                try self.encoder.encode(transaction),
                to: CodexMuxPaths.transaction
            )

            do {
                for write in writes {
                    try self.writeAtomicallyLocked(write.data, to: write.url)
                }

                try? self.appendLogLocked(
                    StorageLogEntry(
                        id: transaction.id,
                        event: event,
                        status: "committed",
                        committedAt: ISO8601DateFormatter().string(from: Date()),
                        touchedPaths: writes.map { $0.url.lastPathComponent }
                    )
                )
                try? self.removeTransactionFileLocked()
            } catch {
                try? self.appendLogLocked(
                    StorageLogEntry(
                        id: transaction.id,
                        event: event,
                        status: "failed",
                        committedAt: ISO8601DateFormatter().string(from: Date()),
                        touchedPaths: writes.map { $0.url.lastPathComponent }
                    )
                )
                throw error
            }
        }
    }

    private func recoverPendingTransactionIfNeededLocked() throws {
        let transactionURL = CodexMuxPaths.transaction

        guard FileManager.default.fileExists(atPath: transactionURL.path(percentEncoded: false)) else {
            return
        }

        let data = try Data(contentsOf: transactionURL)
        let transaction = try self.decoder.decode(PendingTransaction.self, from: data)

        for write in transaction.writes {
            guard let decoded = Data(base64Encoded: write.base64Data) else {
                continue
            }

            try self.writeAtomicallyLocked(
                decoded,
                to: URL(fileURLWithPath: write.path)
            )
        }

        try? self.appendLogLocked(
            StorageLogEntry(
                id: transaction.id,
                event: transaction.event,
                status: "recovered",
                committedAt: ISO8601DateFormatter().string(from: Date()),
                touchedPaths: transaction.writes.map { URL(fileURLWithPath: $0.path).lastPathComponent }
            )
        )
        try self.removeTransactionFileLocked()
    }

    private func ensureRootDirectoryLocked() throws {
        try FileManager.default.createDirectory(
            at: CodexMuxPaths.root,
            withIntermediateDirectories: true
        )
    }

    private func writeAtomicallyLocked(
        _ data: Data,
        to url: URL
    ) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try data.write(to: tempURL)

            let tempHandle = try FileHandle(forWritingTo: tempURL)
            try tempHandle.synchronize()
            try tempHandle.close()

            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }

            let handle = try FileHandle(forWritingTo: url)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private func appendLogLocked(
        _ entry: StorageLogEntry
    ) throws {
        let line = try self.encoder.encode(entry) + Data([0x0A])
        let logURL = CodexMuxPaths.storageLog
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: logURL.path(percentEncoded: false)) {
            try self.writeAtomicallyLocked(line, to: logURL)
            return
        }

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
        try handle.close()
    }

    private func removeTransactionFileLocked() throws {
        let transactionURL = CodexMuxPaths.transaction

        if FileManager.default.fileExists(atPath: transactionURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: transactionURL)
        }
    }
}
