import Foundation
import SQLite3

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum EntryIndexError: Error, LocalizedError, Sendable {
    case sqliteFailure(code: Int32, message: String)
    case closed

    public var errorDescription: String? {
        switch self {
        case let .sqliteFailure(code, message):
            return "SQLite error (\(code)): \(message)"
        case .closed:
            return "EntryIndex database is closed"
        }
    }
}

/// SQLite-backed archive catalog index (`entries` and `directory_nodes` tables with composite indexes).
public final class EntryIndex: @unchecked Sendable {

    public struct MatchStatistics: Codable, Sendable, Hashable {
        public let totalCount: Int
        public let nonAuxiliaryCount: Int

        public init(totalCount: Int, nonAuxiliaryCount: Int) {
            self.totalCount = totalCount
            self.nonAuxiliaryCount = nonAuxiliaryCount
        }
    }

    public let databaseURL: URL
    private let ownsTemporaryDatabase: Bool
    private var database: OpaquePointer?
    private var knownDirectoryNodePaths: Set<String> = []
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseURL: URL? = nil) throws {
        if let providedURL = databaseURL {
            self.databaseURL = providedURL
            self.ownsTemporaryDatabase = false
        } else {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.minato.purezip.indexes", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            self.databaseURL = tempDir.appendingPathComponent("entry-index-\(UUID().uuidString).sqlite3")
            self.ownsTemporaryDatabase = true
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(self.databaseURL.path, &db, flags, nil)
        guard rc == SQLITE_OK, let openedDB = db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let db { sqlite3_close(db) }
            throw EntryIndexError.sqliteFailure(code: rc, message: msg)
        }
        self.database = openedDB

        try executeSQL("PRAGMA journal_mode=WAL;")
        try executeSQL("PRAGMA synchronous=NORMAL;")
        try createSchema()
    }

    deinit {
        close()
        if ownsTemporaryDatabase {
            try? FileManager.default.removeItem(at: databaseURL)
        }
    }

    private func createSchema() throws {
        try executeSQL("""
        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            is_auxiliary INTEGER NOT NULL,
            is_disk_image_background INTEGER NOT NULL,
            is_dmg_applications_shortcut INTEGER NOT NULL,
            payload BLOB NOT NULL
        );
        """)
        try executeSQL("""
        CREATE TABLE IF NOT EXISTS directory_nodes (
            canonical_path TEXT PRIMARY KEY,
            parent_path TEXT NOT NULL,
            sort_name TEXT NOT NULL,
            is_directory INTEGER NOT NULL,
            is_virtual INTEGER NOT NULL,
            is_auxiliary INTEGER NOT NULL,
            is_disk_image_background INTEGER NOT NULL,
            is_dmg_applications_shortcut INTEGER NOT NULL,
            payload BLOB NOT NULL
        );
        """)
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_entries_path ON entries(path COLLATE NOCASE);")
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_entries_path_exact ON entries(path COLLATE BINARY);")
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_directory_nodes_parent_exact ON directory_nodes(parent_path COLLATE BINARY, is_directory DESC, sort_name COLLATE NOCASE);")
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if let db = database {
            sqlite3_close_v2(db)
            database = nil
        }
    }

    public func reset() throws {
        lock.lock()
        defer { lock.unlock() }
        try executeSQL("DELETE FROM entries;")
        try executeSQL("DELETE FROM directory_nodes;")
        knownDirectoryNodePaths.removeAll()
    }

    public func remove(canonicalPaths: [String]) throws {
        guard !canonicalPaths.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        try executeSQL("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let delEntriesSQL = "DELETE FROM entries WHERE path = ? OR path LIKE ?;"
            let delNodesSQL = "DELETE FROM directory_nodes WHERE canonical_path = ? OR canonical_path LIKE ?;"
            var entryStmt: OpaquePointer?
            var nodeStmt: OpaquePointer?
            defer {
                if let entryStmt { sqlite3_finalize(entryStmt) }
                if let nodeStmt { sqlite3_finalize(nodeStmt) }
            }

            guard sqlite3_prepare_v2(db, delEntriesSQL, -1, &entryStmt, nil) == SQLITE_OK else {
                throw currentError(db)
            }
            guard sqlite3_prepare_v2(db, delNodesSQL, -1, &nodeStmt, nil) == SQLITE_OK else {
                throw currentError(db)
            }

            for path in canonicalPaths {
                let prefixPattern = "\(path)/%"
                // 1. Delete from entries
                sqlite3_reset(entryStmt)
                sqlite3_clear_bindings(entryStmt)
                bindText(entryStmt, index: 1, value: path)
                bindText(entryStmt, index: 2, value: prefixPattern)
                guard sqlite3_step(entryStmt) == SQLITE_DONE else {
                    throw currentError(db)
                }

                // 2. Delete from directory_nodes
                sqlite3_reset(nodeStmt)
                sqlite3_clear_bindings(nodeStmt)
                bindText(nodeStmt, index: 1, value: path)
                bindText(nodeStmt, index: 2, value: prefixPattern)
                guard sqlite3_step(nodeStmt) == SQLITE_DONE else {
                    throw currentError(db)
                }

                knownDirectoryNodePaths.remove(path)
            }

            try executeSQL("COMMIT TRANSACTION;")
        } catch {
            try? executeSQL("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    public func rename(oldCanonicalPath: String, to newEntry: ArchiveEntry) throws {
        // 1. Gather all descendants if this was a directory so their subpaths are preserved
        let allDescendants = (try? descendants(of: oldCanonicalPath)) ?? []
        let childEntriesToUpdate: [ArchiveEntry] = allDescendants.compactMap { child in
            guard child.canonicalPath != oldCanonicalPath && child.path != oldCanonicalPath else { return nil }
            let subRel = String(child.path.dropFirst(oldCanonicalPath.count))
            let newSubPath = newEntry.path + subRel
            return ArchiveEntry(
                id: ArchiveBrowserProjection.canonicalEntryPath(newSubPath, isDirectory: child.type == .directory),
                path: newSubPath,
                type: child.type,
                uncompressedSize: child.uncompressedSize,
                compressedSize: child.compressedSize,
                modifiedAt: child.modifiedAt,
                permissions: child.permissions,
                checksum: child.checksum,
                encrypted: child.encrypted,
                linkTarget: child.linkTarget,
                duplicateRecordCount: child.duplicateRecordCount
            )
        }

        // 2. Remove old entry and its descendants
        try remove(canonicalPaths: [oldCanonicalPath])

        // 3. Insert new entry and all updated descendants
        try insert([newEntry] + childEntriesToUpdate)
    }

    public func entry(forID id: String) throws -> ArchiveEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let sql = "SELECT payload FROM entries WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        bindText(stmt, index: 1, value: id)
        let entries = try readEntriesFromStatement(stmt)
        return entries.first
    }

    public func insert(_ batch: [ArchiveEntry]) throws {
        guard !batch.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        try executeSQL("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let entrySQL = "INSERT OR REPLACE INTO entries(id,path,is_auxiliary,is_disk_image_background,is_dmg_applications_shortcut,payload) VALUES(?,?,?,?,?,?);"
            let nodeSQL = """
            INSERT INTO directory_nodes(
                canonical_path,parent_path,sort_name,is_directory,is_virtual,
                is_auxiliary,is_disk_image_background,is_dmg_applications_shortcut,payload
            ) VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(canonical_path) DO UPDATE SET
                is_directory = CASE WHEN excluded.is_directory = 1 THEN 1 ELSE directory_nodes.is_directory END,
                is_virtual = CASE WHEN excluded.is_virtual = 0 THEN 0 ELSE directory_nodes.is_virtual END,
                payload = CASE WHEN excluded.is_virtual = 0 THEN excluded.payload ELSE directory_nodes.payload END;
            """

            var entryStmt: OpaquePointer?
            var nodeStmt: OpaquePointer?
            defer {
                if let entryStmt { sqlite3_finalize(entryStmt) }
                if let nodeStmt { sqlite3_finalize(nodeStmt) }
            }

            guard sqlite3_prepare_v2(db, entrySQL, -1, &entryStmt, nil) == SQLITE_OK else {
                throw currentError(db)
            }
            guard sqlite3_prepare_v2(db, nodeSQL, -1, &nodeStmt, nil) == SQLITE_OK else {
                throw currentError(db)
            }

            for entry in batch {
                let canonicalPath = ArchiveBrowserProjection.canonicalDirectoryPath(entry.path)
                guard !canonicalPath.isEmpty else { continue }

                let payloadData = try encoder.encode(entry)
                let auxInt: Int32 = entry.isAuxiliary ? 1 : 0
                let bgInt: Int32 = entry.isDiskImageBackground ? 1 : 0
                let dmgShortInt: Int32 = entry.isDMGApplicationsShortcut ? 1 : 0

                // 1. Insert into `entries`
                sqlite3_reset(entryStmt)
                sqlite3_clear_bindings(entryStmt)
                bindText(entryStmt, index: 1, value: entry.id)
                bindText(entryStmt, index: 2, value: canonicalPath)
                sqlite3_bind_int(entryStmt, 3, auxInt)
                sqlite3_bind_int(entryStmt, 4, bgInt)
                sqlite3_bind_int(entryStmt, 5, dmgShortInt)
                bindBlob(entryStmt, index: 6, data: payloadData)
                guard sqlite3_step(entryStmt) == SQLITE_DONE else {
                    throw currentError(db)
                }

                // 2. Synthesize virtual ancestor directories in `directory_nodes`
                let components = canonicalPath.split(separator: "/").map(String.init)
                if components.count > 1 {
                    for depth in 1..<components.count {
                        let ancestorPath = components[0..<depth].joined(separator: "/")
                        if !knownDirectoryNodePaths.contains(ancestorPath) {
                            knownDirectoryNodePaths.insert(ancestorPath)
                            let ancestorParent = depth == 1 ? "" : components[0..<(depth - 1)].joined(separator: "/")
                            let ancestorName = components[depth - 1]
                            let virtualEntry = ArchiveEntry(
                                id: ancestorPath,
                                path: ancestorPath,
                                type: .directory
                            )
                            let virtualPayload = try encoder.encode(virtualEntry)
                            sqlite3_reset(nodeStmt)
                            sqlite3_clear_bindings(nodeStmt)
                            bindText(nodeStmt, index: 1, value: ancestorPath)
                            bindText(nodeStmt, index: 2, value: ancestorParent)
                            bindText(nodeStmt, index: 3, value: ancestorName)
                            sqlite3_bind_int(nodeStmt, 4, 1) // is_directory = 1
                            sqlite3_bind_int(nodeStmt, 5, 1) // is_virtual = 1
                            sqlite3_bind_int(nodeStmt, 6, virtualEntry.isAuxiliary ? 1 : 0)
                            sqlite3_bind_int(nodeStmt, 7, virtualEntry.isDiskImageBackground ? 1 : 0)
                            sqlite3_bind_int(nodeStmt, 8, 0)
                            bindBlob(nodeStmt, index: 9, data: virtualPayload)
                            guard sqlite3_step(nodeStmt) == SQLITE_DONE else {
                                throw currentError(db)
                            }
                        }
                    }
                }

                // 3. Insert actual node into `directory_nodes`
                if entry.type == .directory {
                    knownDirectoryNodePaths.insert(canonicalPath)
                }
                let parentPath = components.count == 1 ? "" : components.dropLast().joined(separator: "/")
                let sortName = components.last ?? canonicalPath
                sqlite3_reset(nodeStmt)
                sqlite3_clear_bindings(nodeStmt)
                bindText(nodeStmt, index: 1, value: canonicalPath)
                bindText(nodeStmt, index: 2, value: parentPath)
                bindText(nodeStmt, index: 3, value: sortName)
                sqlite3_bind_int(nodeStmt, 4, entry.type == .directory ? 1 : 0)
                sqlite3_bind_int(nodeStmt, 5, 0) // is_virtual = 0
                sqlite3_bind_int(nodeStmt, 6, auxInt)
                sqlite3_bind_int(nodeStmt, 7, bgInt)
                sqlite3_bind_int(nodeStmt, 8, dmgShortInt)
                bindBlob(nodeStmt, index: 9, data: payloadData)
                guard sqlite3_step(nodeStmt) == SQLITE_DONE else {
                    throw currentError(db)
                }
            }

            try executeSQL("COMMIT;")
        } catch {
            try? executeSQL("ROLLBACK;")
            throw error
        }
    }

    public func children(
        of directoryPath: String,
        offset: Int = 0,
        limit: Int = 1000,
        includeAuxiliary: Bool = false,
        includeDiskImageBackground: Bool = false,
        includeDMGApplicationsShortcut: Bool = false
    ) throws -> [ArchiveEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let canonicalParent = ArchiveBrowserProjection.canonicalDirectoryPath(directoryPath)
        let sql = """
        SELECT payload FROM directory_nodes
        WHERE parent_path = ? COLLATE BINARY
          AND (? OR is_auxiliary = 0)
          AND (? OR is_disk_image_background = 0)
          AND (? OR is_dmg_applications_shortcut = 0)
        ORDER BY is_directory DESC, sort_name COLLATE NOCASE
        LIMIT ? OFFSET ?;
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        bindText(stmt, index: 1, value: canonicalParent)
        sqlite3_bind_int(stmt, 2, includeAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 3, includeDiskImageBackground ? 1 : 0)
        sqlite3_bind_int(stmt, 4, includeDMGApplicationsShortcut ? 1 : 0)
        sqlite3_bind_int64(stmt, 5, Int64(limit))
        sqlite3_bind_int64(stmt, 6, Int64(offset))

        return try readEntriesFromStatement(stmt)
    }

    public func childCount(
        of directoryPath: String,
        includeAuxiliary: Bool = false,
        includeDiskImageBackground: Bool = false,
        includeDMGApplicationsShortcut: Bool = false
    ) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let canonicalParent = ArchiveBrowserProjection.canonicalDirectoryPath(directoryPath)
        let sql = """
        SELECT COUNT(*) FROM directory_nodes
        WHERE parent_path = ? COLLATE BINARY
          AND (? OR is_auxiliary = 0)
          AND (? OR is_disk_image_background = 0)
          AND (? OR is_dmg_applications_shortcut = 0);
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        bindText(stmt, index: 1, value: canonicalParent)
        sqlite3_bind_int(stmt, 2, includeAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 3, includeDiskImageBackground ? 1 : 0)
        sqlite3_bind_int(stmt, 4, includeDMGApplicationsShortcut ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw currentError(db)
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    public func childStatistics(
        of directoryPath: String,
        treatsDiskImageBackgroundAsAuxiliary: Bool = true,
        treatsDMGApplicationsShortcutAsAuxiliary: Bool = true
    ) throws -> MatchStatistics {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let canonicalParent = ArchiveBrowserProjection.canonicalDirectoryPath(directoryPath)
        let sql = """
        SELECT COUNT(*), COALESCE(SUM(CASE WHEN is_auxiliary = 0
            AND (? = 0 OR is_disk_image_background = 0)
            AND (? = 0 OR is_dmg_applications_shortcut = 0)
            THEN 1 ELSE 0 END), 0)
        FROM directory_nodes
        WHERE parent_path = ? COLLATE BINARY;
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        sqlite3_bind_int(stmt, 1, treatsDiskImageBackgroundAsAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 2, treatsDMGApplicationsShortcutAsAuxiliary ? 1 : 0)
        bindText(stmt, index: 3, value: canonicalParent)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw currentError(db)
        }
        return MatchStatistics(
            totalCount: Int(sqlite3_column_int64(stmt, 0)),
            nonAuxiliaryCount: Int(sqlite3_column_int64(stmt, 1))
        )
    }

    public func page(
        search: String,
        offset: Int = 0,
        limit: Int = 500,
        includeAuxiliary: Bool = false,
        includeDiskImageBackground: Bool = false,
        includeDMGApplicationsShortcut: Bool = false
    ) throws -> [ArchiveEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = """
        SELECT payload FROM entries
        WHERE (? = '' OR path LIKE '%' || ? || '%' COLLATE NOCASE)
          AND (? OR is_auxiliary = 0)
          AND (? OR is_disk_image_background = 0)
          AND (? OR is_dmg_applications_shortcut = 0)
        ORDER BY path COLLATE NOCASE
        LIMIT ? OFFSET ?;
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        bindText(stmt, index: 1, value: trimmed)
        bindText(stmt, index: 2, value: trimmed)
        sqlite3_bind_int(stmt, 3, includeAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 4, includeDiskImageBackground ? 1 : 0)
        sqlite3_bind_int(stmt, 5, includeDMGApplicationsShortcut ? 1 : 0)
        sqlite3_bind_int64(stmt, 6, Int64(limit))
        sqlite3_bind_int64(stmt, 7, Int64(offset))

        return try readEntriesFromStatement(stmt)
    }

    public func pageCount(
        search: String,
        includeAuxiliary: Bool = false,
        includeDiskImageBackground: Bool = false,
        includeDMGApplicationsShortcut: Bool = false
    ) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = """
        SELECT COUNT(*) FROM entries
        WHERE (? = '' OR path LIKE '%' || ? || '%' COLLATE NOCASE)
          AND (? OR is_auxiliary = 0)
          AND (? OR is_disk_image_background = 0)
          AND (? OR is_dmg_applications_shortcut = 0);
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        bindText(stmt, index: 1, value: trimmed)
        bindText(stmt, index: 2, value: trimmed)
        sqlite3_bind_int(stmt, 3, includeAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 4, includeDiskImageBackground ? 1 : 0)
        sqlite3_bind_int(stmt, 5, includeDMGApplicationsShortcut ? 1 : 0)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw currentError(db)
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Searches for top-level or single-subfolder nested application bundle roots (`.app`).
    public func findApplicationBundles(limit: Int = 10) throws -> [ArchiveEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        // Find entries whose path ends in .app or contains .app/ where the directory level is shallow (<= 2 slashes)
        let sql = """
        SELECT payload FROM entries
        WHERE (path LIKE '%.app' OR path LIKE '%.app/' OR name LIKE '%.app')
          AND is_auxiliary = 0
          AND is_disk_image_background = 0
        ORDER BY path COLLATE NOCASE
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        sqlite3_bind_int64(stmt, 1, Int64(limit))
        return try readEntriesFromStatement(stmt)
    }

    /// Subtree range query for all descendant entries under `directoryPath`:
    /// `SELECT payload FROM entries WHERE path = ? COLLATE BINARY OR (path >= ? COLLATE BINARY AND path < ? COLLATE BINARY) ORDER BY path COLLATE NOCASE;`
    public func descendants(of directoryPath: String) throws -> [ArchiveEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let canonical = ArchiveBrowserProjection.canonicalDirectoryPath(directoryPath)
        guard !canonical.isEmpty else {
            return try page(search: "", offset: 0, limit: Int.max, includeAuxiliary: true, includeDiskImageBackground: true, includeDMGApplicationsShortcut: true)
        }

        let lowerBound = canonical + "/"
        let upperBound = canonical + "0" // ASCII '0' (0x30) immediately follows '/' (0x2F)
        let sql = """
        SELECT payload FROM entries
        WHERE path = ? COLLATE BINARY
           OR (path >= ? COLLATE BINARY AND path < ? COLLATE BINARY)
        ORDER BY path COLLATE NOCASE;
        """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }
        bindText(stmt, index: 1, value: canonical)
        bindText(stmt, index: 2, value: lowerBound)
        bindText(stmt, index: 3, value: upperBound)

        return try readEntriesFromStatement(stmt)
    }

    /// Checks which candidate paths exist as directories in `directory_nodes` using:
    /// `SELECT 1 FROM directory_nodes WHERE canonical_path = ? COLLATE BINARY AND is_directory = 1;`
    public func existingDirectoryAncestors(for paths: [String]) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let sql = "SELECT 1 FROM directory_nodes WHERE canonical_path = ? COLLATE BINARY AND is_directory = 1;"
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw currentError(db)
        }

        var result: [String] = []
        for path in paths {
            let canonical = ArchiveBrowserProjection.canonicalDirectoryPath(path)
            guard !canonical.isEmpty else { continue }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            bindText(stmt, index: 1, value: canonical)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result.append(canonical)
            }
        }
        return result
    }

    public func count() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db = database else { throw EntryIndexError.closed }

        let sql = "SELECT COUNT(*) FROM entries;"
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            throw currentError(db)
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Private SQLite Helpers

    private func executeSQL(_ sql: String) throws {
        guard let db = database else { throw EntryIndexError.closed }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "SQL execution failed"
            if let errMsg { sqlite3_free(errMsg) }
            throw EntryIndexError.sqliteFailure(code: rc, message: msg)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        _ = value.withCString { cStr in
            sqlite3_bind_text(stmt, index, cStr, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        }
    }

    private func bindBlob(_ stmt: OpaquePointer?, index: Int32, data: Data) {
        _ = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, index, rawBuffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT_DESTRUCTOR)
        }
    }

    private func readEntriesFromStatement(_ stmt: OpaquePointer?) throws -> [ArchiveEntry] {
        var results: [ArchiveEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let byteCount = Int(sqlite3_column_bytes(stmt, 0))
            if byteCount > 0, let rawPtr = sqlite3_column_blob(stmt, 0) {
                let data = Data(bytes: rawPtr, count: byteCount)
                let entry = try decoder.decode(ArchiveEntry.self, from: data)
                results.append(entry)
            }
        }
        return results
    }

    private func currentError(_ db: OpaquePointer) -> EntryIndexError {
        let code = sqlite3_errcode(db)
        let msg = String(cString: sqlite3_errmsg(db))
        return .sqliteFailure(code: code, message: msg)
    }
}
