import Foundation

public struct ArchivePreviewSeedHandle: Codable, Sendable, Hashable {
    public let id: UUID
    public let directoryURL: URL

    public init(id: UUID = UUID(), directoryURL: URL) {
        self.id = id
        self.directoryURL = directoryURL
    }
}

public struct ArchivePreviewSeedClaim: Codable, Sendable, Hashable {
    public let fingerprint: ArchiveSourceFingerprint
    public let format: ArchiveFormat
    public let entries: [ArchiveEntry]
    public let thumbnails: [String: Data]
    public let isAuthoritativeForAppListing: Bool

    public init(
        fingerprint: ArchiveSourceFingerprint,
        format: ArchiveFormat,
        entries: [ArchiveEntry],
        thumbnails: [String: Data] = [:],
        isAuthoritativeForAppListing: Bool
    ) {
        self.fingerprint = fingerprint
        self.format = format
        self.entries = entries
        self.thumbnails = thumbnails
        self.isAuthoritativeForAppListing = isAuthoritativeForAppListing
    }
}

public enum ArchivePreviewSeedPolicy {
    public static let supportedFormats: Set<ArchiveFormat> = [
        .zip, .sevenZip, .rar, .tar, .gzip, .bzip2, .xz, .lzip, .iso, .dmg
    ]

    public static func supports(_ format: ArchiveFormat) -> Bool {
        supportedFormats.contains(format)
    }
}

/// Shared preview seed store between `PureZipQuickLook.appex` and `PureZip.app`.
public actor ArchivePreviewSeedStore {
    public static let maximumEntryCount = 10_000
    public static let maximumManifestByteCount = 8 * 1024 * 1024
    public static let maximumThumbnailCount = 64
    public static let maximumThumbnailByteCount = 512 * 1024
    public static let maximumPublishedSeedCount = 16
    public static let maximumTotalByteCount: UInt64 = 64 * 1024 * 1024

    public let rootDirectory: URL
    public let maximumAge: TimeInterval
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct ManifestRecord: Codable {
        let id: UUID
        let createdAt: Date
        let fingerprint: ArchiveSourceFingerprint
        let format: ArchiveFormat
        let entries: [ArchiveEntry]
        let isAuthoritativeForAppListing: Bool
        var thumbnailFiles: [String: String]
    }

    public init(
        rootDirectory: URL? = nil,
        maximumAge: TimeInterval = 300,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory
            .appendingPathComponent("com.minato.purezip.previews", isDirectory: true)
        self.maximumAge = maximumAge
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    public func publish(
        fingerprint: ArchiveSourceFingerprint,
        format: ArchiveFormat,
        entries: [ArchiveEntry],
        isAuthoritativeForAppListing: Bool,
        now: Date = Date()
    ) throws -> ArchivePreviewSeedHandle {
        try? removeCleanableData(now: now)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let id = UUID()
        let seedDir = rootDirectory.appendingPathComponent("seed-\(id.uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: seedDir, withIntermediateDirectories: true)

        let cappedEntries = Array(entries.prefix(Self.maximumEntryCount))
        let manifest = ManifestRecord(
            id: id,
            createdAt: now,
            fingerprint: fingerprint,
            format: format,
            entries: cappedEntries,
            isAuthoritativeForAppListing: isAuthoritativeForAppListing,
            thumbnailFiles: [:]
        )
        let data = try encoder.encode(manifest)
        let manifestURL = seedDir.appendingPathComponent("manifest.json")
        try data.write(to: manifestURL, options: .atomic)

        return ArchivePreviewSeedHandle(id: id, directoryURL: seedDir)
    }

    public func storeThumbnail(
        _ data: Data,
        for entryID: String,
        in handle: ArchivePreviewSeedHandle,
        now: Date = Date()
    ) throws {
        guard data.count <= Self.maximumThumbnailByteCount else { return }
        let manifestURL = handle.directoryURL.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              var manifest = try? decoder.decode(ManifestRecord.self, from: manifestData) else {
            return
        }
        guard manifest.thumbnailFiles.count < Self.maximumThumbnailCount else { return }

        let imageFileName = "thumb-\(UUID().uuidString).bin"
        let thumbURL = handle.directoryURL.appendingPathComponent(imageFileName)
        try data.write(to: thumbURL, options: .atomic)
        manifest.thumbnailFiles[entryID] = imageFileName

        let updated = try encoder.encode(manifest)
        try updated.write(to: manifestURL, options: .atomic)
    }

    public func claim(
        matching fingerprint: ArchiveSourceFingerprint,
        now: Date = Date()
    ) async throws -> ArchivePreviewSeedClaim? {
        try? removeCleanableData(now: now)
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        for dir in children where dir.lastPathComponent.hasPrefix("seed-") {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(ManifestRecord.self, from: data) else {
                continue
            }
            if now.timeIntervalSince(manifest.createdAt) <= maximumAge &&
               manifest.fingerprint == fingerprint {
                var thumbnails: [String: Data] = [:]
                for (entryID, fileName) in manifest.thumbnailFiles {
                    let thumbURL = dir.appendingPathComponent(fileName)
                    if let thumbData = try? Data(contentsOf: thumbURL) {
                        thumbnails[entryID] = thumbData
                    }
                }
                try? fileManager.removeItem(at: dir)
                return ArchivePreviewSeedClaim(
                    fingerprint: manifest.fingerprint,
                    format: manifest.format,
                    entries: manifest.entries,
                    thumbnails: thumbnails,
                    isAuthoritativeForAppListing: manifest.isAuthoritativeForAppListing
                )
            }
        }
        return nil
    }

    public func discard(_ handle: ArchivePreviewSeedHandle) {
        try? fileManager.removeItem(at: handle.directoryURL)
    }

    public func cleanableDirectories(now: Date = Date()) throws -> [URL] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }
        var stale: [URL] = []
        for dir in children {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? decoder.decode(ManifestRecord.self, from: data) {
                if now.timeIntervalSince(manifest.createdAt) > maximumAge {
                    stale.append(dir)
                }
            } else {
                stale.append(dir)
            }
        }
        return stale
    }

    public func removeCleanableData(now: Date = Date()) throws {
        for url in try cleanableDirectories(now: now) {
            try? fileManager.removeItem(at: url)
        }
    }
}
