import Foundation
import SQLite3
import Darwin

private let SQLITE_TRANSIENT_DESTRUCTOR_REG = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - ManagedTemporaryArtifact Enums & Models

public enum ManagedTemporaryArtifactPurpose: String, Codable, Sendable, Hashable {
    case archiveCreation
    case archiveUpdate
    case extraction
    case finderQuickCompression
    case applicationInstallation
    case fontInstallation
    case streamExtraction
    case shelfCollection
}

public enum ManagedTemporaryArtifactKind: String, Codable, Sendable, Hashable {
    case file
    case directory
}

public enum ManagedTemporaryArtifactState: String, Codable, Sendable, Hashable {
    case reserved
    case writing
    case validated
    case publishing
    case cleanupPending
    case recoveryAvailable
    case ownershipUncertain
    case published
}

public struct ArchivePublicationPlan: Codable, Sendable, Hashable {
    public struct MemberPlan: Codable, Sendable, Hashable {
        public let stagedURL: URL
        public let finalURL: URL
        public let backupURL: URL?

        public init(stagedURL: URL, finalURL: URL, backupURL: URL? = nil) {
            self.stagedURL = stagedURL
            self.finalURL = finalURL
            self.backupURL = backupURL
        }
    }

    public let primaryURL: URL
    public let members: [MemberPlan]

    public init(primaryURL: URL, members: [MemberPlan]) {
        self.primaryURL = primaryURL
        self.members = members
    }
}

// MARK: - ManagedArchivePublicationLease

/// Transactional archive publication lease (`commit() async throws -> ArchiveCreationResult`, `rollbackAndWait() async`).
public struct ManagedArchivePublicationLease: Sendable {
    public let transactionID: UUID
    public let result: ArchiveCreationResult
    public let plan: ArchivePublicationPlan
    private let registry: ManagedTemporaryArtifactRegistry

    public init(
        transactionID: UUID,
        result: ArchiveCreationResult,
        plan: ArchivePublicationPlan,
        registry: ManagedTemporaryArtifactRegistry
    ) {
        self.transactionID = transactionID
        self.result = result
        self.plan = plan
        self.registry = registry
    }

    public var stagedPrimaryURL: URL {
        plan.members.first?.stagedURL ?? result.primaryURL
    }

    public func commit() async throws -> ArchiveCreationResult {
        try await registry.commitPublication(transactionID: transactionID, plan: plan, result: result)
    }

    public func rollbackAndWait() async {
        await registry.rollbackPublication(transactionID: transactionID, plan: plan)
    }
}

// MARK: - ManagedTemporaryArtifactRegistry

/// Actor managing the SQLite-backed `archive_publications` and `temporary_artifacts` ledger.
public actor ManagedTemporaryArtifactRegistry {
    public let databaseURL: URL
    public let sessionIdentifier: String
    public let processIdentifier: Int32
    private var databaseHandle: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseURL: URL? = nil, sessionIdentifier: String = UUID().uuidString) throws {
        self.sessionIdentifier = sessionIdentifier
        self.processIdentifier = ProcessInfo.processInfo.processIdentifier

        if let provided = databaseURL {
            self.databaseURL = provided
            try FileManager.default.createDirectory(
                at: provided.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } else {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.minato.purezip.ledger", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.databaseURL = dir.appendingPathComponent("temporary-artifacts-\(sessionIdentifier).sqlite3")
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(self.databaseURL.path, &db, flags, nil)
        guard rc == SQLITE_OK, let opened = db else {
            if let db { sqlite3_close(db) }
            throw EntryIndexError.sqliteFailure(code: rc, message: "Could not open artifact registry database")
        }
        self.databaseHandle = opened
        try Self.initializeSchema(on: opened)
    }

    private static func initializeSchema(on db: OpaquePointer) throws {
        let statements = [
            "PRAGMA journal_mode=WAL;",
            """
            CREATE TABLE IF NOT EXISTS archive_publications (
                transaction_id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                process_id INTEGER NOT NULL,
                ownership_token TEXT NOT NULL,
                state TEXT NOT NULL,
                parent_path TEXT NOT NULL,
                volume_uuid TEXT,
                bookmark BLOB,
                plan BLOB NOT NULL,
                reserved_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS temporary_artifacts (
                artifact_id TEXT PRIMARY KEY,
                operation_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                process_id INTEGER NOT NULL,
                purpose TEXT NOT NULL,
                path TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                ownership_token TEXT NOT NULL,
                state TEXT NOT NULL,
                volume_uuid TEXT,
                bookmark BLOB,
                device_id INTEGER,
                inode INTEGER,
                file_type INTEGER,
                birth_seconds INTEGER,
                birth_nanoseconds INTEGER,
                size_bytes INTEGER,
                reserved_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_archive_publications_session
            ON archive_publications(session_id, process_id, state);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_temporary_artifacts_session
            ON temporary_artifacts(session_id, process_id, state);
            """
        ]

        for sql in statements {
            var errMsg: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
            if rc != SQLITE_OK {
                let message = errMsg.map { String(cString: $0) } ?? "Schema error"
                if let errMsg { sqlite3_free(errMsg) }
                throw EntryIndexError.sqliteFailure(code: rc, message: message)
            }
        }
    }

    public func reserveArchivePublication(
        finalURL: URL,
        splitMemberCount: Int? = nil,
        purpose: ManagedTemporaryArtifactPurpose = .archiveCreation
    ) throws -> ManagedArchivePublicationLease {
        guard let db = databaseHandle else { throw EntryIndexError.closed }

        let transactionID = UUID()
        let ownershipToken = UUID().uuidString
        let destinationURLs = ArchiveOutputFamily.destinationMemberURLs(
            at: finalURL,
            splitMemberCount: splitMemberCount
        )
        let parentDir = finalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let members: [ArchivePublicationPlan.MemberPlan] = destinationURLs.map { dest in
            let stagedName = ".\(dest.lastPathComponent).purezip-staged-\(transactionID.uuidString.prefix(8))"
            let stagedURL = parentDir.appendingPathComponent(stagedName)
            let backupURL = parentDir.appendingPathComponent(".\(dest.lastPathComponent).purezip-backup-\(transactionID.uuidString.prefix(8))")
            return ArchivePublicationPlan.MemberPlan(
                stagedURL: stagedURL,
                finalURL: dest,
                backupURL: backupURL
            )
        }

        let plan = ArchivePublicationPlan(primaryURL: destinationURLs.first ?? finalURL, members: members)
        let planBlob = try encoder.encode(plan)
        let now = Date().timeIntervalSince1970

        let insertPubSQL = """
        INSERT INTO archive_publications (
            transaction_id, session_id, process_id,
            ownership_token, state, parent_path,
            volume_uuid, bookmark, plan,
            reserved_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, insertPubSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw EntryIndexError.sqliteFailure(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        bindText(stmt, index: 1, value: transactionID.uuidString)
        bindText(stmt, index: 2, value: sessionIdentifier)
        sqlite3_bind_int(stmt, 3, processIdentifier)
        bindText(stmt, index: 4, value: ownershipToken)
        bindText(stmt, index: 5, value: ManagedTemporaryArtifactState.reserved.rawValue)
        bindText(stmt, index: 6, value: parentDir.path)
        sqlite3_bind_null(stmt, 7)
        sqlite3_bind_null(stmt, 8)
        bindBlob(stmt, index: 9, data: planBlob)
        sqlite3_bind_double(stmt, 10, now)
        sqlite3_bind_double(stmt, 11, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw EntryIndexError.sqliteFailure(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }

        // Also register each staged member in `temporary_artifacts`
        for member in members {
            try registerTemporaryArtifact(
                operationID: transactionID,
                purpose: purpose,
                url: member.stagedURL,
                kind: .file,
                ownershipToken: ownershipToken
            )
        }

        let creationResult = ArchiveCreationResult(
            primaryURL: plan.primaryURL,
            memberURLs: destinationURLs
        )
        return ManagedArchivePublicationLease(
            transactionID: transactionID,
            result: creationResult,
            plan: plan,
            registry: self
        )
    }

    public func registerTemporaryArtifact(
        operationID: UUID = UUID(),
        purpose: ManagedTemporaryArtifactPurpose,
        url: URL,
        kind: ManagedTemporaryArtifactKind,
        ownershipToken: String = UUID().uuidString
    ) throws {
        guard let db = databaseHandle else { throw EntryIndexError.closed }
        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO temporary_artifacts (
            artifact_id, operation_id, session_id, process_id,
            purpose, path, kind, ownership_token, state,
            volume_uuid, bookmark, device_id, inode, file_type,
            birth_seconds, birth_nanoseconds, size_bytes,
            reserved_at, updated_at, retry_count
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, 0
        );
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw EntryIndexError.sqliteFailure(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        bindText(stmt, index: 1, value: UUID().uuidString)
        bindText(stmt, index: 2, value: operationID.uuidString)
        bindText(stmt, index: 3, value: sessionIdentifier)
        sqlite3_bind_int(stmt, 4, processIdentifier)
        bindText(stmt, index: 5, value: purpose.rawValue)
        bindText(stmt, index: 6, value: url.path)
        bindText(stmt, index: 7, value: kind.rawValue)
        bindText(stmt, index: 8, value: ownershipToken)
        bindText(stmt, index: 9, value: ManagedTemporaryArtifactState.reserved.rawValue)
        for idx in 10...17 {
            sqlite3_bind_null(stmt, Int32(idx))
        }
        sqlite3_bind_double(stmt, 18, now)
        sqlite3_bind_double(stmt, 19, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw EntryIndexError.sqliteFailure(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
    }

    internal func commitPublication(
        transactionID: UUID,
        plan: ArchivePublicationPlan,
        result: ArchiveCreationResult
    ) throws -> ArchiveCreationResult {
        let fm = FileManager.default
        try updatePublicationState(transactionID: transactionID, state: .publishing)

        do {
            for member in plan.members {
                if fm.fileExists(atPath: member.stagedURL.path) {
                    if fm.fileExists(atPath: member.finalURL.path) {
                        try fm.removeItem(at: member.finalURL)
                    }
                    try fm.moveItem(at: member.stagedURL, to: member.finalURL)
                    try updateArtifactState(path: member.stagedURL.path, state: .published)
                } else {
                    // Check for multi-volume split files (e.g. .001, .002, ...)
                    let parent = member.stagedURL.deletingLastPathComponent()
                    let prefix = member.stagedURL.lastPathComponent
                    let siblings = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []
                    let splitStaged = siblings.filter { $0.hasPrefix(prefix) }.sorted()
                    if !splitStaged.isEmpty {
                        for stagedName in splitStaged {
                            let stagedPartURL = parent.appendingPathComponent(stagedName)
                            let suffix = String(stagedName.dropFirst(prefix.count))
                            let finalPartURL = parent.appendingPathComponent(member.finalURL.lastPathComponent + suffix)
                            if fm.fileExists(atPath: finalPartURL.path) {
                                try fm.removeItem(at: finalPartURL)
                            }
                            try fm.moveItem(at: stagedPartURL, to: finalPartURL)
                            try updateArtifactState(path: stagedPartURL.path, state: .published)
                        }
                    } else {
                        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: member.stagedURL.path])
                    }
                }
            }
            try updatePublicationState(transactionID: transactionID, state: .published)
            return result
        } catch {
            try? updatePublicationState(transactionID: transactionID, state: .recoveryAvailable, lastError: error.localizedDescription)
            throw error
        }
    }

    internal func rollbackPublication(transactionID: UUID, plan: ArchivePublicationPlan) {
        let fm = FileManager.default
        for member in plan.members {
            if fm.fileExists(atPath: member.stagedURL.path) {
                try? fm.removeItem(at: member.stagedURL)
            }
            let parent = member.stagedURL.deletingLastPathComponent()
            let prefix = member.stagedURL.lastPathComponent
            let siblings = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []
            for splitName in siblings where splitName.hasPrefix(prefix) {
                try? fm.removeItem(at: parent.appendingPathComponent(splitName))
            }
            if let backup = member.backupURL, fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: backup)
            }
            try? updateArtifactState(path: member.stagedURL.path, state: .cleanupPending)
        }
        try? deletePublicationRecord(transactionID: transactionID)
    }

    public func publicationCount() throws -> Int {
        guard let db = databaseHandle else { throw EntryIndexError.closed }
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM archive_publications;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            throw EntryIndexError.sqliteFailure(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    public func artifactCount() throws -> Int {
        guard let db = databaseHandle else { throw EntryIndexError.closed }
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM temporary_artifacts;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            throw EntryIndexError.sqliteFailure(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func updatePublicationState(
        transactionID: UUID,
        state: ManagedTemporaryArtifactState,
        lastError: String? = nil
    ) throws {
        guard let db = databaseHandle else { throw EntryIndexError.closed }
        let sql = "UPDATE archive_publications SET state = ?, updated_at = ?, last_error = ? WHERE transaction_id = ?;"
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bindText(stmt, index: 1, value: state.rawValue)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        if let lastError {
            bindText(stmt, index: 3, value: lastError)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        bindText(stmt, index: 4, value: transactionID.uuidString)
        _ = sqlite3_step(stmt)
    }

    private func updateArtifactState(path: String, state: ManagedTemporaryArtifactState) throws {
        guard let db = databaseHandle else { throw EntryIndexError.closed }
        let sql = "UPDATE temporary_artifacts SET state = ?, updated_at = ? WHERE path = ?;"
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bindText(stmt, index: 1, value: state.rawValue)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        bindText(stmt, index: 3, value: path)
        _ = sqlite3_step(stmt)
    }

    private func deletePublicationRecord(transactionID: UUID) throws {
        guard let db = databaseHandle else { throw EntryIndexError.closed }
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, "DELETE FROM archive_publications WHERE transaction_id = ?;", -1, &stmt, nil) == SQLITE_OK else { return }
        bindText(stmt, index: 1, value: transactionID.uuidString)
        _ = sqlite3_step(stmt)
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        _ = value.withCString { cStr in
            sqlite3_bind_text(stmt, index, cStr, -1, SQLITE_TRANSIENT_DESTRUCTOR_REG)
        }
    }

    private func bindBlob(_ stmt: OpaquePointer?, index: Int32, data: Data) {
        _ = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, index, rawBuffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT_DESTRUCTOR_REG)
        }
    }
}

// MARK: - ManagedWorkFileStore & ManagedWorkFileLease

public final class ManagedWorkFileLease: @unchecked Sendable {
    public let id: UUID
    public let url: URL
    private weak var store: ManagedWorkFileStore?
    private let lock = NSLock()
    private var isReleased = false

    internal init(id: UUID, url: URL, store: ManagedWorkFileStore) {
        self.id = id
        self.url = url
        self.store = store
    }

    public func release() {
        lock.lock()
        guard !isReleased else {
            lock.unlock()
            return
        }
        isReleased = true
        lock.unlock()
        store?.releaseLease(id: id, url: url)
    }

    deinit {
        release()
    }
}

public final class ManagedWorkFileStore: @unchecked Sendable {
    public static let shared = ManagedWorkFileStore()

    public let rootDirectory: URL
    private let lock = NSLock()
    private var live: [UUID: URL] = [:]

    public init(rootDirectory: URL? = nil) {
        let base = rootDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("com.minato.purezip.workfiles", isDirectory: true)
        self.rootDirectory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    public func register(_ url: URL) throws -> ManagedWorkFileLease {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let id = UUID()
        lock.lock()
        live[id] = url
        lock.unlock()
        return ManagedWorkFileLease(id: id, url: url, store: self)
    }

    public func makeStagingLease(prefix: String = "stage") throws -> ManagedWorkFileLease {
        let dir = rootDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        return try register(dir)
    }

    public func manages(_ url: URL) -> Bool {
        let std = url.standardizedFileURL.path
        let rootStd = rootDirectory.standardizedFileURL.path
        return std.hasPrefix(rootStd)
    }

    internal func releaseLease(id: UUID, url: URL) {
        lock.lock()
        live.removeValue(forKey: id)
        lock.unlock()
        try? FileManager.default.removeItem(at: url)
    }

    private func snapshotActivePaths() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(live.values.map { $0.standardizedFileURL.path })
    }

    public func clean() async throws -> Int {
        let activePaths = snapshotActivePaths()

        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var removed = 0
        for child in children {
            if !activePaths.contains(child.standardizedFileURL.path) {
                try? fm.removeItem(at: child)
                removed += 1
            }
        }
        return removed
    }
}
