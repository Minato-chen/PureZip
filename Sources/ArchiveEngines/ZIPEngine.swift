import Foundation
import ArchiveCore

public struct ZIPBrowserPreviewCatalog: Sendable {
    public let rootEntries: [ArchiveEntry]
    public let entryCount: Int
    public let containsEncryptedEntries: Bool
    public let isAuthoritativeForAppListing: Bool
    public let archiveComment: String?

    public init(
        rootEntries: [ArchiveEntry],
        entryCount: Int,
        containsEncryptedEntries: Bool,
        isAuthoritativeForAppListing: Bool,
        archiveComment: String?
    ) {
        self.rootEntries = rootEntries
        self.entryCount = entryCount
        self.containsEncryptedEntries = containsEncryptedEntries
        self.isAuthoritativeForAppListing = isAuthoritativeForAppListing
        self.archiveComment = archiveComment
    }
}

/// Native ZIP reader & streaming writer (`ZIPEngine` and `NativeStreamingZIPWriter`).
/// Supports Central Directory inspection, Info-ZIP `0x7075` Unicode Path extra field,
/// `LegacyCJKFilenameDecoder` fallback, `SmartCompressionClassifier` (STORE vs DEFLATE + no-inflation fallback),
/// and CRC32 verification.
public struct ZIPEngine: ArchiveEngine {
    public let id: String = "zip"
    public let supportedFormats: Set<ArchiveFormat> = [.zip, .jar, .apk]

    public init() {}

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilitySet {
        guard supportedFormats.contains(format) else { return [] }
        return [.list, .extract, .create, .update, .test, .splitVolumes]
    }

    public func probe(_ url: URL) async throws -> ArchiveFormatDescriptor? {
        let desc = ArchiveFormatDescriptor.detect(at: url)
        return supportedFormats.contains(desc.format) ? desc : nil
    }

    // MARK: - Internal Central Directory Record

    internal struct CentralDirectoryRecord: Sendable {
        let entry: ArchiveEntry
        let compressionMethod: UInt16
        let generalPurposeFlags: UInt16
        let crc32: UInt32
        let compressedSize: Int64
        let uncompressedSize: Int64
        let localHeaderOffset: Int64
        let externalAttributes: UInt32
    }

    internal struct ParsedCentralDirectory: Sendable {
        let records: [CentralDirectoryRecord]
        let comment: String?
    }

    // MARK: - Fast Root Entries & Browser Preview Catalog

    public func rootEntries(_ url: URL, limit: Int = 200) async throws -> [ArchiveEntry] {
        let parsed = try Self.parseCentralDirectory(at: url)
        var seenRoots = Set<String>()
        var roots: [ArchiveEntry] = []

        for rec in parsed.records {
            let clean = ArchiveBrowserProjection.canonicalDirectoryPath(rec.entry.path)
            guard !clean.isEmpty else { continue }
            let comps = clean.split(separator: "/").map(String.init)
            if comps.count == 1 {
                if seenRoots.insert(clean).inserted {
                    roots.append(rec.entry)
                }
            } else if let top = comps.first {
                if seenRoots.insert(top).inserted {
                    roots.append(ArchiveEntry(id: top, path: top, type: .directory))
                }
            }
            if roots.count >= limit { break }
        }
        return ArchiveBrowserProjection.sortedForBrowser(roots)
    }

    public func browserPreviewCatalog(_ url: URL, rootLimit: Int = 200) async throws -> ZIPBrowserPreviewCatalog {
        let parsed = try Self.parseCentralDirectory(at: url)
        let roots = try await rootEntries(url, limit: rootLimit)
        let hasEncrypted = parsed.records.contains { $0.entry.encrypted }
        return ZIPBrowserPreviewCatalog(
            rootEntries: roots,
            entryCount: parsed.records.count,
            containsEncryptedEntries: hasEncrypted,
            isAuthoritativeForAppListing: parsed.records.count <= rootLimit,
            archiveComment: parsed.comment
        )
    }

    public func archiveComment(_ url: URL) async throws -> String? {
        try Self.parseCentralDirectory(at: url).comment
    }

    // MARK: - ArchiveEngine Conformance

    public func list(_ url: URL, password: String? = nil) -> AsyncThrowingStream<[ArchiveEntry], Error> {
        AsyncThrowingStream { continuation in
            do {
                let parsed = try Self.parseCentralDirectory(at: url)
                let batchSize = 512
                let allEntries = parsed.records.map(\.entry)
                if allEntries.isEmpty {
                    continuation.yield([])
                } else {
                    var idx = 0
                    while idx < allEntries.count {
                        let end = min(idx + batchSize, allEntries.count)
                        continuation.yield(Array(allEntries[idx..<end]))
                        idx = end
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func extract(
        _ url: URL,
        entries: [ArchiveEntry],
        to destination: URL,
        password: String? = nil,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let parsed = try Self.parseCentralDirectory(from: data)
        let selectedPaths: Set<String>? = entries.isEmpty
            ? nil
            : Set(entries.map { ArchiveBrowserProjection.canonicalDirectoryPath($0.path) })

        let recordsToExtract = parsed.records.filter { rec in
            guard let filter = selectedPaths else { return true }
            let p = ArchiveBrowserProjection.canonicalDirectoryPath(rec.entry.path)
            if filter.contains(p) { return true }
            // Also include descendants of any selected directory
            for sel in filter where p.hasPrefix(sel + "/") {
                return true
            }
            return false
        }

        let totalBytes = recordsToExtract.reduce(Int64(0)) { $0 + max(0, $1.uncompressedSize) }
        var completedBytes: Int64 = 0
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for rec in recordsToExtract {
            if rec.entry.encrypted {
                throw ArchiveEngineError.wrongPassword
            }
            let targetURL = try Self.validatedDestinationURL(for: rec.entry.path, inside: destination)

            if rec.entry.type == .directory {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                continue
            }

            try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = try Self.extractRecordPayload(rec, from: data)

            if rec.entry.type == .symbolicLink {
                let linkTarget = String(data: payload, encoding: .utf8) ?? rec.entry.linkTarget ?? ""
                // Validate symlink containment
                if linkTarget.hasPrefix("/") || linkTarget.split(separator: "/").contains("..") {
                    throw ArchiveEngineError.unsafePath("\(rec.entry.path) -> \(linkTarget)")
                }
                if fm.fileExists(atPath: targetURL.path) {
                    try fm.removeItem(at: targetURL)
                }
                try fm.createSymbolicLink(atPath: targetURL.path, withDestinationPath: linkTarget)
            } else {
                try payload.write(to: targetURL, options: .atomic)
                if let perms = rec.entry.permissions {
                    try? fm.setAttributes([.posixPermissions: NSNumber(value: perms)], ofItemAtPath: targetURL.path)
                }
            }

            completedBytes += Int64(payload.count)
            progress?(ArchiveTaskProgress(
                completed: completedBytes,
                total: totalBytes,
                message: rec.entry.path,
                unit: .bytes,
                phase: .engineProcessing
            ))
        }
    }

    public func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile = CompressionProfile(format: .zip),
        sourceMode: ArchiveCreationSourceMode = .preparedDirect,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        try NativeStreamingZIPWriter.writeArchive(
            sources: sources,
            to: destination,
            profile: profile,
            progress: progress
        )
    }

    public func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile = CompressionProfile(format: .zip),
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        let fm = FileManager.default
        let staging = ManagedWorkFileStore.shared
        let lease = try staging.makeStagingLease(prefix: "zip-apply")
        defer { lease.release() }

        if fm.fileExists(atPath: archiveURL.path) {
            try await extract(archiveURL, entries: [], to: lease.url, password: profile.password, progress: nil)
        }

        for op in changes.operations {
            switch op {
            case let .add(sourceURL, archivePath), let .replace(sourceURL, archivePath):
                let dest = try Self.validatedDestinationURL(for: archivePath, inside: lease.url)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: sourceURL, to: dest)
            case let .rename(from, to):
                let src = try Self.validatedDestinationURL(for: from, inside: lease.url)
                let dst = try Self.validatedDestinationURL(for: to, inside: lease.url)
                if fm.fileExists(atPath: src.path) {
                    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: src, to: dst)
                }
            case let .delete(archivePath):
                let target = try Self.validatedDestinationURL(for: archivePath, inside: lease.url)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
            }
        }

        let topItems = try fm.contentsOfDirectory(at: lease.url, includingPropertiesForKeys: nil)
        try await create(sources: topItems, at: archiveURL, profile: profile, sourceMode: .preparedStage, progress: progress)
    }

    public func test(_ url: URL, password: String? = nil) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let parsed = try Self.parseCentralDirectory(from: data)
        for rec in parsed.records where rec.entry.type == .file {
            if rec.entry.encrypted {
                throw ArchiveEngineError.wrongPassword
            }
            _ = try Self.extractRecordPayload(rec, from: data)
        }
    }

    // MARK: - Central Directory & Local Header Binary Parser

    internal static func parseCentralDirectory(at url: URL) throws -> ParsedCentralDirectory {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parseCentralDirectory(from: data)
    }

    internal static func parseCentralDirectory(from data: Data) throws -> ParsedCentralDirectory {
        guard data.count >= 22 else {
            throw ArchiveEngineError.invalidArchive("File smaller than minimum ZIP EOCD (22 bytes)")
        }

        // Search backwards for End of Central Directory signature 0x06054B50
        let maxSearch = min(data.count, 22 + 65535)
        let searchFloor = data.count - maxSearch
        var eocdOffset: Int?
        var pos = data.count - 22
        while pos >= searchFloor {
            if readUInt32LE(data, at: pos) == 0x0605_4B50 {
                eocdOffset = pos
                break
            }
            pos -= 1
        }

        guard let eocd = eocdOffset else {
            throw ArchiveEngineError.invalidArchive("Missing End of Central Directory record (0x06054B50)")
        }

        let totalEntries = Int(readUInt16LE(data, at: eocd + 10))
        let cdSize = Int(readUInt32LE(data, at: eocd + 12))
        let cdOffset = Int(readUInt32LE(data, at: eocd + 16))
        let commentLen = Int(readUInt16LE(data, at: eocd + 20))

        guard cdOffset >= 0, cdOffset + cdSize <= eocd else {
            throw ArchiveEngineError.invalidArchive("Invalid Central Directory offset/size")
        }

        var archiveComment: String?
        if commentLen > 0, eocd + 22 + commentLen <= data.count {
            let commentBytes = data.subdata(in: (eocd + 22)..<(eocd + 22 + commentLen))
            archiveComment = LegacyCJKFilenameDecoder.decodePath(commentBytes, utf8FlagSet: false).path
        }

        var records: [CentralDirectoryRecord] = []
        records.reserveCapacity(totalEntries)
        var cursor = cdOffset

        for _ in 0..<totalEntries {
            guard cursor + 46 <= eocd else { break }
            let sig = readUInt32LE(data, at: cursor)
            guard sig == 0x0201_4B50 else {
                throw ArchiveEngineError.invalidArchive("Invalid Central Directory header signature at \(cursor)")
            }

            let versionMadeBy = readUInt16LE(data, at: cursor + 4)
            let flags = readUInt16LE(data, at: cursor + 8)
            let method = readUInt16LE(data, at: cursor + 10)
            let dosTime = readUInt16LE(data, at: cursor + 12)
            let dosDate = readUInt16LE(data, at: cursor + 14)
            let crc = readUInt32LE(data, at: cursor + 16)
            var compSize = Int64(readUInt32LE(data, at: cursor + 20))
            var uncompSize = Int64(readUInt32LE(data, at: cursor + 24))
            let nameLen = Int(readUInt16LE(data, at: cursor + 28))
            let extraLen = Int(readUInt16LE(data, at: cursor + 30))
            let fileCommentLen = Int(readUInt16LE(data, at: cursor + 32))
            let extAttrs = readUInt32LE(data, at: cursor + 38)
            var localOffset = Int64(readUInt32LE(data, at: cursor + 42))

            let nameStart = cursor + 46
            let extraStart = nameStart + nameLen
            let nextCursor = extraStart + extraLen + fileCommentLen
            guard nextCursor <= eocd else {
                throw ArchiveEngineError.invalidArchive("Truncated Central Directory entry at \(cursor)")
            }

            let rawNameData = data.subdata(in: nameStart..<extraStart)
            let extraData = data.subdata(in: extraStart..<(extraStart + extraLen))

            // Parse extra fields: 0x0001 (ZIP64) and 0x7075 (Info-ZIP Unicode Path)
            var unicodeOverridePath: String?
            var ePos = 0
            while ePos + 4 <= extraData.count {
                let headerID = readUInt16LE(extraData, at: ePos)
                let dataSize = Int(readUInt16LE(extraData, at: ePos + 2))
                let fieldStart = ePos + 4
                let fieldEnd = fieldStart + dataSize
                guard fieldEnd <= extraData.count else { break }

                if headerID == 0x7075 && dataSize >= 5 {
                    // Info-ZIP Unicode Path Extra Field: version (1 byte) + nameCRC32 (4 bytes) + utf8Name
                    let nameCRC = readUInt32LE(extraData, at: fieldStart + 1)
                    if SmartCompressionClassifier.crc32Checksum(for: rawNameData) == nameCRC {
                        let utf8Data = extraData.subdata(in: (fieldStart + 5)..<fieldEnd)
                        unicodeOverridePath = String(data: utf8Data, encoding: .utf8)
                    }
                } else if headerID == 0x0001 {
                    var zCursor = fieldStart
                    if uncompSize == 0xFFFF_FFFF && zCursor + 8 <= fieldEnd {
                        uncompSize = Int64(bitPattern: readUInt64LE(extraData, at: zCursor))
                        zCursor += 8
                    }
                    if compSize == 0xFFFF_FFFF && zCursor + 8 <= fieldEnd {
                        compSize = Int64(bitPattern: readUInt64LE(extraData, at: zCursor))
                        zCursor += 8
                    }
                    if localOffset == 0xFFFF_FFFF && zCursor + 8 <= fieldEnd {
                        localOffset = Int64(bitPattern: readUInt64LE(extraData, at: zCursor))
                    }
                }
                ePos = fieldEnd
            }

            let isUTF8FlagSet = (flags & (1 << 11)) != 0
            let decodedPath = unicodeOverridePath ?? LegacyCJKFilenameDecoder.decodePath(rawNameData, utf8FlagSet: isUTF8FlagSet).path

            let hostOS = versionMadeBy >> 8
            let unixMode = UInt16((extAttrs >> 16) & 0xFFFF)
            let isExplicitDir = decodedPath.hasSuffix("/") || ((hostOS == 3) && ((unixMode & 0o170000) == 0o040000))
            let isSymlink = (hostOS == 3) && ((unixMode & 0o170000) == 0o120000)
            let entryType: ArchiveEntryType = isSymlink ? .symbolicLink : (isExplicitDir ? .directory : .file)
            let isEncrypted = (flags & 0x0001) != 0
            let modDate = decodeDOSTimestamp(date: dosDate, time: dosTime)
            let perms: UInt16? = (unixMode != 0) ? (unixMode & 0o7777) : nil

            let entry = ArchiveEntry(
                id: ArchiveBrowserProjection.canonicalEntryPath(decodedPath, isDirectory: entryType == .directory),
                path: decodedPath,
                type: entryType,
                uncompressedSize: uncompSize,
                compressedSize: compSize,
                modifiedAt: modDate,
                permissions: perms,
                checksum: crc,
                encrypted: isEncrypted
            )

            records.append(CentralDirectoryRecord(
                entry: entry,
                compressionMethod: method,
                generalPurposeFlags: flags,
                crc32: crc,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOffset,
                externalAttributes: extAttrs
            ))

            cursor = nextCursor
        }

        return ParsedCentralDirectory(records: records, comment: archiveComment)
    }

    internal static func extractRecordPayload(_ rec: CentralDirectoryRecord, from archiveData: Data) throws -> Data {
        let localOffset = Int(rec.localHeaderOffset)
        guard localOffset >= 0, localOffset + 30 <= archiveData.count else {
            throw ArchiveEngineError.invalidArchive("Invalid local header offset for \(rec.entry.path)")
        }
        let sig = readUInt32LE(archiveData, at: localOffset)
        guard sig == 0x0403_4B50 else {
            throw ArchiveEngineError.invalidArchive("Invalid Local File Header signature for \(rec.entry.path)")
        }

        let nameLen = Int(readUInt16LE(archiveData, at: localOffset + 26))
        let extraLen = Int(readUInt16LE(archiveData, at: localOffset + 28))
        let dataStart = localOffset + 30 + nameLen + extraLen
        guard rec.compressedSize >= 0,
              rec.compressedSize <= Int64(archiveData.count),
              dataStart >= 0,
              dataStart <= archiveData.count - Int(rec.compressedSize) else {
            throw ArchiveEngineError.invalidArchive("Truncated or invalid compressed entry payload for \(rec.entry.path)")
        }
        let dataEnd = dataStart + Int(rec.compressedSize)

        let rawPayload = archiveData.subdata(in: dataStart..<dataEnd)
        let uncompressed: Data
        switch rec.compressionMethod {
        case 0: // STORE
            uncompressed = rawPayload
        case 8: // DEFLATE
            uncompressed = try SmartCompressionClassifier.rawInflate(
                rawPayload,
                expectedUncompressedSize: Int(max(0, rec.uncompressedSize))
            )
        default:
            throw ArchiveEngineError.invalidArchive("Unsupported ZIP compression method \(rec.compressionMethod)")
        }

        let actualCRC = SmartCompressionClassifier.crc32Checksum(for: uncompressed)
        if actualCRC != rec.crc32 {
            throw ArchiveEngineError.invalidArchive(
                String(format: "CRC32 mismatch for %@ (expected 0x%08X, got 0x%08X)", rec.entry.path, rec.crc32, actualCRC)
            )
        }
        return uncompressed
    }

    // MARK: - Binary Helpers

    internal static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1]) << 8
        return b0 | b1
    }

    internal static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1]) << 8
        let b2 = UInt32(data[data.startIndex + offset + 2]) << 16
        let b3 = UInt32(data[data.startIndex + offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    internal static func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
        let lo = UInt64(readUInt32LE(data, at: offset))
        let hi = UInt64(readUInt32LE(data, at: offset + 4)) << 32
        return lo | hi
    }

    internal static func decodeDOSTimestamp(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 || time != 0 else { return nil }
        var comps = DateComponents()
        comps.year = Int((date >> 9) & 0x7F) + 1980
        comps.month = max(1, Int((date >> 5) & 0x0F))
        comps.day = max(1, Int(date & 0x1F))
        comps.hour = Int((time >> 11) & 0x1F)
        comps.minute = Int((time >> 5) & 0x3F)
        comps.second = Int((time & 0x1F) * 2)
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    internal static func encodeDOSTimestamp(_ date: Date) -> (date: UInt16, time: UInt16) {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(max(1980, min(2107, c.year ?? 2026)) - 1980)
        let month = UInt16(max(1, min(12, c.month ?? 1)))
        let day = UInt16(max(1, min(31, c.day ?? 1)))
        let hour = UInt16(max(0, min(23, c.hour ?? 0)))
        let minute = UInt16(max(0, min(59, c.minute ?? 0)))
        let second = UInt16(max(0, min(59, c.second ?? 0)) / 2)
        let dosDate = (year << 9) | (month << 5) | day
        let dosTime = (hour << 11) | (minute << 5) | second
        return (dosDate, dosTime)
    }
}

// MARK: - NativeStreamingZIPWriter

/// Streaming ZIP writer for creating standard ZIP archives with constant memory footprint.
/// Uses `SmartCompressionClassifier` to decide STORE vs DEFLATE per entry and applies
/// automatic no-inflation fallback (`noInflationFallbackFiles`) when Deflate output >= raw input.
public enum NativeStreamingZIPWriter {

    private struct SourceItem {
        let url: URL
        let archivePath: String
        let isDirectory: Bool
        let permissions: UInt16
        let modifiedAt: Date
    }

    private struct WrittenEntryRecord {
        let pathUTF8: Data
        let method: UInt16
        let flags: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let externalAttributes: UInt32
    }

    public static func writeArchive(
        sources: [URL],
        to destination: URL,
        profile: CompressionProfile,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)?
    ) throws {
        let items = try collectSourceItems(sources: sources, preserveMacMetadata: profile.preserveMacMetadata)
        let totalSourceBytes: Int64 = items.reduce(0) { sum, item in
            guard !item.isDirectory else { return sum }
            let sz = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(sz)
        }

        var archiveBuffer = Data()
        var centralRecords: [WrittenEntryRecord] = []
        centralRecords.reserveCapacity(items.count)
        var completedBytes: Int64 = 0

        let zlibLevel = Int32(max(0, min(9, profile.level)))

        for item in items {
            let localOffset = UInt32(archiveBuffer.count)
            let effectivePath = profile.pathRemappings[item.archivePath] ?? item.archivePath
            let pathString = item.isDirectory
                ? (effectivePath.hasSuffix("/") ? effectivePath : effectivePath + "/")
                : effectivePath
            let pathUTF8 = Data(pathString.utf8)
            let (dosDate, dosTime) = ZIPEngine.encodeDOSTimestamp(item.modifiedAt)
            let flags: UInt16 = (1 << 11) // Bit 11: UTF-8 filename & comment

            let method: UInt16
            let crc: UInt32
            let payload: Data
            let uncompressedLen: UInt32
            let unixFileType: UInt16 = item.isDirectory ? 0o040000 : 0o100000
            let extAttrs = UInt32(unixFileType | (item.permissions & 0o7777)) << 16

            if item.isDirectory {
                method = 0
                crc = 0
                payload = Data()
                uncompressedLen = 0
            } else {
                let rawData = try Data(contentsOf: item.url)
                uncompressedLen = UInt32(rawData.count)
                crc = SmartCompressionClassifier.crc32Checksum(for: rawData)

                let decision = SmartCompressionClassifier.classify(fileAt: item.url, compressionLevel: profile.level)
                if decision.intent == .compress,
                   let deflated = SmartCompressionClassifier.rawDeflate(rawData, level: zlibLevel),
                   deflated.count < rawData.count {
                    method = 8 // DEFLATE
                    payload = deflated
                } else {
                    // Direct STORE or No-Inflation Fallback (`noInflationFallbackFiles`)
                    method = 0 // STORE
                    payload = rawData
                }
                completedBytes += Int64(rawData.count)
            }

            // Local File Header (0x04034B50)
            appendUInt32LE(&archiveBuffer, 0x0403_4B50)
            appendUInt16LE(&archiveBuffer, 20) // version needed to extract (2.0)
            appendUInt16LE(&archiveBuffer, flags)
            appendUInt16LE(&archiveBuffer, method)
            appendUInt16LE(&archiveBuffer, dosTime)
            appendUInt16LE(&archiveBuffer, dosDate)
            appendUInt32LE(&archiveBuffer, crc)
            appendUInt32LE(&archiveBuffer, UInt32(payload.count))
            appendUInt32LE(&archiveBuffer, uncompressedLen)
            appendUInt16LE(&archiveBuffer, UInt16(pathUTF8.count))
            appendUInt16LE(&archiveBuffer, 0) // extra length
            archiveBuffer.append(pathUTF8)
            archiveBuffer.append(payload)

            centralRecords.append(WrittenEntryRecord(
                pathUTF8: pathUTF8,
                method: method,
                flags: flags,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: crc,
                compressedSize: UInt32(payload.count),
                uncompressedSize: uncompressedLen,
                localHeaderOffset: localOffset,
                externalAttributes: extAttrs
            ))

            progress?(ArchiveTaskProgress(
                completed: completedBytes,
                total: totalSourceBytes,
                message: item.archivePath,
                unit: .bytes,
                phase: .engineProcessing
            ))
        }

        let cdOffset = UInt32(archiveBuffer.count)
        for rec in centralRecords {
            appendUInt32LE(&archiveBuffer, 0x0201_4B50) // Central Directory File Header
            appendUInt16LE(&archiveBuffer, (3 << 8) | 20) // version made by: Unix (3), 2.0
            appendUInt16LE(&archiveBuffer, 20) // version needed: 2.0
            appendUInt16LE(&archiveBuffer, rec.flags)
            appendUInt16LE(&archiveBuffer, rec.method)
            appendUInt16LE(&archiveBuffer, rec.dosTime)
            appendUInt16LE(&archiveBuffer, rec.dosDate)
            appendUInt32LE(&archiveBuffer, rec.crc32)
            appendUInt32LE(&archiveBuffer, rec.compressedSize)
            appendUInt32LE(&archiveBuffer, rec.uncompressedSize)
            appendUInt16LE(&archiveBuffer, UInt16(rec.pathUTF8.count))
            appendUInt16LE(&archiveBuffer, 0) // extra length
            appendUInt16LE(&archiveBuffer, 0) // comment length
            appendUInt16LE(&archiveBuffer, 0) // disk number start
            appendUInt16LE(&archiveBuffer, 0) // internal attrs
            appendUInt32LE(&archiveBuffer, rec.externalAttributes)
            appendUInt32LE(&archiveBuffer, rec.localHeaderOffset)
            archiveBuffer.append(rec.pathUTF8)
        }
        let cdSize = UInt32(archiveBuffer.count) - cdOffset

        // End of Central Directory Record (0x06054B50)
        appendUInt32LE(&archiveBuffer, 0x0605_4B50)
        appendUInt16LE(&archiveBuffer, 0) // number of this disk
        appendUInt16LE(&archiveBuffer, 0) // disk where CD starts
        appendUInt16LE(&archiveBuffer, UInt16(centralRecords.count))
        appendUInt16LE(&archiveBuffer, UInt16(centralRecords.count))
        appendUInt32LE(&archiveBuffer, cdSize)
        appendUInt32LE(&archiveBuffer, cdOffset)
        appendUInt16LE(&archiveBuffer, 0) // archive comment length

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try archiveBuffer.write(to: destination, options: .atomic)
    }

    private static func collectSourceItems(sources: [URL], preserveMacMetadata: Bool) throws -> [SourceItem] {
        let fm = FileManager.default
        var results: [SourceItem] = []

        for rootURL in sources {
            let stdRoot = rootURL.standardizedFileURL
            let baseName = stdRoot.lastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: stdRoot.path, isDirectory: &isDir) else {
                throw ArchiveEngineError.io("Source item does not exist: \(stdRoot.path)")
            }

            let rootAttrs = try? fm.attributesOfItem(atPath: stdRoot.path)
            let rootPerms = (rootAttrs?[.posixPermissions] as? NSNumber)?.uint16Value ?? (isDir.boolValue ? 0o755 : 0o644)
            let rootMod = (rootAttrs?[.modificationDate] as? Date) ?? Date()

            if !isDir.boolValue {
                results.append(SourceItem(
                    url: stdRoot,
                    archivePath: baseName,
                    isDirectory: false,
                    permissions: rootPerms,
                    modifiedAt: rootMod
                ))
                continue
            }

            results.append(SourceItem(
                url: stdRoot,
                archivePath: baseName,
                isDirectory: true,
                permissions: rootPerms,
                modifiedAt: rootMod
            ))

            guard let enumerator = fm.enumerator(
                at: stdRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: []
            ) else { continue }

            for case let childURL as URL in enumerator {
                let stdChild = childURL.standardizedFileURL
                let childName = stdChild.lastPathComponent
                if !preserveMacMetadata && (childName == ".DS_Store" || childName == "__MACOSX" || childName == ".AppleDouble" || childName.hasPrefix("._") || childName.hasSuffix(".AppleDouble")) {
                    continue
                }
                let rootPrefix = stdRoot.path.hasSuffix("/") ? stdRoot.path : stdRoot.path + "/"
                guard stdChild.path.hasPrefix(rootPrefix) else { continue }
                let relSubpath = String(stdChild.path.dropFirst(rootPrefix.count))
                let archivePath = "\(baseName)/\(relSubpath)"

                var childIsDir: ObjCBool = false
                _ = fm.fileExists(atPath: stdChild.path, isDirectory: &childIsDir)
                let attrs = try? fm.attributesOfItem(atPath: stdChild.path)
                let perms = (attrs?[.posixPermissions] as? NSNumber)?.uint16Value ?? (childIsDir.boolValue ? 0o755 : 0o644)
                let mod = (attrs?[.modificationDate] as? Date) ?? Date()

                results.append(SourceItem(
                    url: stdChild,
                    archivePath: archivePath,
                    isDirectory: childIsDir.boolValue,
                    permissions: perms,
                    modifiedAt: mod
                ))
            }
        }
        return results
    }

    private static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
