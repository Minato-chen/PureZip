import Foundation
import Darwin

// MARK: - ArchiveSupportTier

public enum ArchiveSupportTier: String, Codable, CaseIterable, Sendable, Hashable {
    case complete
    case reliable
    case experimental
}

// MARK: - ArchiveCapabilitySet

public struct ArchiveCapabilitySet: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let list         = ArchiveCapabilitySet(rawValue: 1 << 0)
    public static let extract      = ArchiveCapabilitySet(rawValue: 1 << 1)
    public static let create       = ArchiveCapabilitySet(rawValue: 1 << 2)
    public static let update       = ArchiveCapabilitySet(rawValue: 1 << 3)
    public static let encrypt      = ArchiveCapabilitySet(rawValue: 1 << 4)
    public static let test         = ArchiveCapabilitySet(rawValue: 1 << 5)
    public static let splitVolumes = ArchiveCapabilitySet(rawValue: 1 << 6)
}

// MARK: - ArchiveFormat

/// Supported archive and compressed stream formats in PureZip.
public enum ArchiveFormat: String, Codable, CaseIterable, Sendable, Hashable {
    case zip
    case sevenZip
    case rar
    case tar
    case gzip
    case bzip2
    case xz
    case lzip
    case lzma
    case dmg
    case iso
    case cbr
    case exe
    case msi
    case lha
    case cpio
    case cab
    case jar
    case pak
    case pkg
    case apk
    case arj
    case spk
    case rpm
    case ace
    case lbr
    case nsa
    case cpt
    case swf
    case unknown
}

// MARK: - ArchiveFormatDescriptor

public struct ArchiveFormatDescriptor: Codable, Sendable, Hashable, Identifiable {
    public var id: ArchiveFormat { format }
    public let format: ArchiveFormat
    public let displayName: String
    public let extensions: [String]
    public let tier: ArchiveSupportTier
    public let capabilities: ArchiveCapabilitySet
    public let signedContainer: Bool

    public init(
        format: ArchiveFormat,
        displayName: String,
        extensions: [String],
        tier: ArchiveSupportTier,
        capabilities: ArchiveCapabilitySet,
        signedContainer: Bool = false
    ) {
        self.format = format
        self.displayName = displayName
        self.extensions = extensions
        self.tier = tier
        self.capabilities = capabilities
        self.signedContainer = signedContainer
    }

    public static let catalog: [ArchiveFormat: ArchiveFormatDescriptor] = [
        .zip: ArchiveFormatDescriptor(
            format: .zip,
            displayName: "ZIP Archive",
            extensions: ["zip", "cbz"],
            tier: .complete,
            capabilities: [.list, .extract, .create, .update, .encrypt, .test, .splitVolumes]
        ),
        .sevenZip: ArchiveFormatDescriptor(
            format: .sevenZip,
            displayName: "7-Zip Archive",
            extensions: ["7z"],
            tier: .complete,
            capabilities: [.list, .extract, .create, .update, .encrypt, .test, .splitVolumes]
        ),
        .rar: ArchiveFormatDescriptor(
            format: .rar,
            displayName: "RAR Archive",
            extensions: ["rar"],
            tier: .reliable,
            capabilities: [.list, .extract, .test, .splitVolumes]
        ),
        .tar: ArchiveFormatDescriptor(
            format: .tar,
            displayName: "POSIX TAR Archive",
            extensions: ["tar", "tgz", "tbz2", "txz"],
            tier: .complete,
            capabilities: [.list, .extract, .create, .update, .test]
        ),
        .gzip: ArchiveFormatDescriptor(
            format: .gzip,
            displayName: "Gzip Compressed Stream",
            extensions: ["gz", "gzip"],
            tier: .complete,
            capabilities: [.list, .extract, .create, .test]
        ),
        .bzip2: ArchiveFormatDescriptor(
            format: .bzip2,
            displayName: "Bzip2 Compressed Stream",
            extensions: ["bz2", "bzip2"],
            tier: .complete,
            capabilities: [.list, .extract, .create, .test]
        ),
        .xz: ArchiveFormatDescriptor(
            format: .xz,
            displayName: "XZ Compressed Stream",
            extensions: ["xz"],
            tier: .complete,
            capabilities: [.list, .extract, .create, .test]
        ),
        .lzip: ArchiveFormatDescriptor(
            format: .lzip,
            displayName: "Lzip Archive",
            extensions: ["lz", "tlz"],
            tier: .reliable,
            capabilities: [.list, .extract, .create, .test]
        ),
        .lzma: ArchiveFormatDescriptor(
            format: .lzma,
            displayName: "LZMA Stream",
            extensions: ["lzma"],
            tier: .reliable,
            capabilities: [.list, .extract, .test]
        ),
        .dmg: ArchiveFormatDescriptor(
            format: .dmg,
            displayName: "Apple Disk Image",
            extensions: ["dmg"],
            tier: .reliable,
            capabilities: [.list, .extract, .test],
            signedContainer: true
        ),
        .iso: ArchiveFormatDescriptor(
            format: .iso,
            displayName: "ISO 9660 Disk Image",
            extensions: ["iso"],
            tier: .reliable,
            capabilities: [.list, .extract, .test]
        ),
        .jar: ArchiveFormatDescriptor(
            format: .jar,
            displayName: "Java Archive",
            extensions: ["jar", "war"],
            tier: .complete,
            capabilities: [.list, .extract, .test],
            signedContainer: true
        ),
        .apk: ArchiveFormatDescriptor(
            format: .apk,
            displayName: "Android Package",
            extensions: ["apk"],
            tier: .reliable,
            capabilities: [.list, .extract, .test],
            signedContainer: true
        ),
        .pkg: ArchiveFormatDescriptor(
            format: .pkg,
            displayName: "macOS Installer Package",
            extensions: ["pkg", "xip"],
            tier: .reliable,
            capabilities: [.list, .extract, .test],
            signedContainer: true
        ),
        .cpio: ArchiveFormatDescriptor(
            format: .cpio,
            displayName: "CPIO Archive",
            extensions: ["cpio"],
            tier: .reliable,
            capabilities: [.list, .extract, .test]
        ),
        .cab: ArchiveFormatDescriptor(
            format: .cab,
            displayName: "Microsoft Cabinet",
            extensions: ["cab"],
            tier: .reliable,
            capabilities: [.list, .extract, .test]
        )
    ]

    public static func descriptor(for format: ArchiveFormat) -> ArchiveFormatDescriptor {
        if let desc = catalog[format] {
            return desc
        }
        return ArchiveFormatDescriptor(
            format: format,
            displayName: format.rawValue.uppercased(),
            extensions: [format.rawValue],
            tier: .experimental,
            capabilities: [.list, .extract]
        )
    }

    /// Probes a file URL by magic bytes first, then by filename / split-volume extension.
    public static func detect(at url: URL) -> ArchiveFormatDescriptor {
        let lowerName = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let nonArchiveExtensions: Set<String> = [
            "xlsx", "xlsm", "xlsb", "xltx",
            "docx", "docm", "dotx",
            "pptx", "pptm", "potx",
            "pages", "key", "numbers",
            "odt", "ods", "odp",
            "epub", "vsdx", "drawio"
        ]
        if nonArchiveExtensions.contains(ext) {
            return descriptor(for: .unknown)
        }

        if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") ||
           lowerName.hasSuffix(".tar.bz2") || lowerName.hasSuffix(".tbz2") ||
           lowerName.hasSuffix(".tar.xz") || lowerName.hasSuffix(".txz") {
            return descriptor(for: .tar)
        }
        if lowerName.hasSuffix(".tar.lz") || lowerName.hasSuffix(".tlz") {
            return descriptor(for: .lzip)
        }
        if ext == "dmg" {
            return descriptor(for: .dmg)
        }
        if ext == "iso" {
            return descriptor(for: .iso)
        }

        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let magic = try? handle.read(upToCount: 512), !magic.isEmpty {
                let bytes = [UInt8](magic)
                // ZIP magic: PK\x03\x04, PK\x05\x06 (empty), PK\x07\x08 (spanned)
                if bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B &&
                    (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) {
                    if lowerName.hasSuffix(".jar") { return descriptor(for: .jar) }
                    if lowerName.hasSuffix(".apk") { return descriptor(for: .apk) }
                    return descriptor(for: .zip)
                }
                // 7z magic: 37 7A BC AF 27 1C
                if bytes.count >= 6 &&
                    bytes[0] == 0x37 && bytes[1] == 0x7A && bytes[2] == 0xBC &&
                    bytes[3] == 0xAF && bytes[4] == 0x27 && bytes[5] == 0x1C {
                    return descriptor(for: .sevenZip)
                }
                // RAR magic: 52 61 72 21 1A 07
                if bytes.count >= 6 &&
                    bytes[0] == 0x52 && bytes[1] == 0x61 && bytes[2] == 0x72 &&
                    bytes[3] == 0x21 && bytes[4] == 0x1A && bytes[5] == 0x07 {
                    return descriptor(for: .rar)
                }
                // LZIP magic: "LZIP" (4C 5A 49 50)
                if bytes.count >= 4 &&
                    bytes[0] == 0x4C && bytes[1] == 0x5A && bytes[2] == 0x49 && bytes[3] == 0x50 {
                    return descriptor(for: .lzip)
                }
                // Gzip magic: 1F 8B
                if bytes.count >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B {
                    return descriptor(for: .gzip)
                }
                // Bzip2 magic: "BZh" (42 5A 68)
                if bytes.count >= 3 && bytes[0] == 0x42 && bytes[1] == 0x5A && bytes[2] == 0x68 {
                    return descriptor(for: .bzip2)
                }
                // XZ magic: FD 37 7A 58 5A 00
                if bytes.count >= 6 &&
                    bytes[0] == 0xFD && bytes[1] == 0x37 && bytes[2] == 0x7A &&
                    bytes[3] == 0x58 && bytes[4] == 0x5A && bytes[5] == 0x00 {
                    return descriptor(for: .xz)
                }
                // POSIX ustar TAR magic at offset 257: "ustar"
                if bytes.count >= 262 &&
                    bytes[257] == 0x75 && bytes[258] == 0x73 && bytes[259] == 0x74 &&
                    bytes[260] == 0x61 && bytes[261] == 0x72 {
                    return descriptor(for: .tar)
                }
            }
        }

        // Fallback to extension inspection
        for (_, desc) in catalog where desc.extensions.contains(ext) {
            return desc
        }
        if let fmt = ArchiveFormat(rawValue: ext) {
            return descriptor(for: fmt)
        }
        if ArchiveVolumeFamily.isSplitArchive(at: url) {
            let parts = lowerName.split(separator: ".")
            if parts.count >= 3 {
                let innerExt = String(parts[parts.count - 2])
                for (_, desc) in catalog where desc.extensions.contains(innerExt) {
                    return desc
                }
            }
            return descriptor(for: .sevenZip)
        }
        return descriptor(for: .unknown)
    }
}

// MARK: - ArchiveEntry

public enum ArchiveEntryType: String, Codable, Sendable, Hashable {
    case file
    case directory
    case symbolicLink
    case hardLink
    case other
}

public struct ArchiveEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let path: String
    public let type: ArchiveEntryType
    public let uncompressedSize: Int64
    public let compressedSize: Int64
    public let modifiedAt: Date?
    public let permissions: UInt16?
    public let checksum: UInt32?
    public let encrypted: Bool
    public let linkTarget: String?
    public let duplicateRecordCount: Int

    public init(
        id: String? = nil,
        path: String,
        type: ArchiveEntryType,
        uncompressedSize: Int64 = 0,
        compressedSize: Int64 = 0,
        modifiedAt: Date? = nil,
        permissions: UInt16? = nil,
        checksum: UInt32? = nil,
        encrypted: Bool = false,
        linkTarget: String? = nil,
        duplicateRecordCount: Int = 0
    ) {
        let normalized = ArchiveBrowserProjection.canonicalEntryPath(path, isDirectory: type == .directory)
        self.id = id ?? normalized
        self.path = normalized
        self.type = type
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.modifiedAt = modifiedAt
        self.permissions = permissions
        self.checksum = checksum
        self.encrypted = encrypted
        self.linkTarget = linkTarget
        self.duplicateRecordCount = duplicateRecordCount
    }

    public var name: String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let slash = trimmed.lastIndex(of: "/") {
            return String(trimmed[trimmed.index(after: slash)...])
        }
        return trimmed
    }

    public var parentPath: String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let slash = trimmed.lastIndex(of: "/") else {
            return ""
        }
        return String(trimmed[..<slash])
    }

    public var canonicalPath: String {
        ArchiveBrowserProjection.canonicalDirectoryPath(path)
    }

    /// Auxiliary macOS metadata entries (`__MACOSX`, `.DS_Store`, `._*` AppleDouble, raw disk partitions, HFS+ private system structures).
    public var isAuxiliary: Bool {
        let comps = path.split(separator: "/")
        if comps.contains("__MACOSX") { return true }
        if comps.contains(".fseventsd") || comps.contains(".Trashes") { return true }
        guard let last = comps.last else { return false }
        if last == ".DS_Store" || last.hasPrefix("._") { return true }
        let lastStr = String(last)
        let lowerLast = lastStr.lowercased()
        if lowerLast.contains("[hfs+ private data]") || lowerLast.contains(".hfs+ private directory data") ||
            lowerLast.contains("hfs+ private") {
            return true
        }
        if lowerLast.hasSuffix(".apfs") || lowerLast.hasSuffix(".hfs") || lowerLast.hasSuffix(".hfsx") ||
            lastStr == "0.Apple_partition_map" || lastStr == "0.MBR" ||
            lastStr.contains("Apple_APFS") || lastStr.contains("Apple_HFS") ||
            lastStr.contains("Primary GPT") || lastStr.contains("Backup GPT") ||
            lowerLast.contains("disk image") || lowerLast.contains("free space") {
            return true
        }
        return false
    }

    /// Disk image hidden `.background` directory or files.
    public var isDiskImageBackground: Bool {
        let comps = path.split(separator: "/")
        return comps.contains(".background")
    }

    /// Disk image top-level `Applications` symlink pointing to `/Applications`.
    public var isDMGApplicationsShortcut: Bool {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed == "Applications" && type == .symbolicLink && (linkTarget == "/Applications" || linkTarget == nil)
    }

    /// Detects whether this entry is a nested archive container based on its filename extension.
    public var nestedArchiveDescriptor: ArchiveFormatDescriptor? {
        guard type != .directory && type != .symbolicLink else { return nil }
        let dummyURL = URL(fileURLWithPath: "/tmp/\(name)")
        let desc = ArchiveFormatDescriptor.detect(at: dummyURL)
        return desc.format != .unknown ? desc : nil
    }

    /// True if this entry is a nested archive file (`.zip`, `.7z`, `.rar`, `.tar.gz`, `.dmg`, `.iso`, etc.).
    public var isNestedArchive: Bool {
        nestedArchiveDescriptor != nil
    }
}

// MARK: - ArchiveBrowserProjection

public enum ArchiveBrowserProjection {
    public static func canonicalDirectoryPath(_ path: String) -> String {
        let parts = path.split(separator: "/").filter { !$0.isEmpty && $0 != "." }
        return parts.joined(separator: "/")
    }

    public static func canonicalEntryPath(_ path: String, isDirectory: Bool) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/").filter { !$0.isEmpty && $0 != "." }
        return parts.joined(separator: "/")
    }

    public static func sortedForBrowser(_ entries: [ArchiveEntry]) -> [ArchiveEntry] {
        entries.sorted { lhs, rhs in
            let lDir = lhs.type == .directory
            let rDir = rhs.type == .directory
            if lDir != rDir {
                return lDir && !rDir
            }
            let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.path < rhs.path
        }
    }

    public static func directChildren(
        of entries: [ArchiveEntry],
        in directoryPath: String,
        includeAuxiliary: Bool = false
    ) -> [ArchiveEntry] {
        let index = DirectChildrenIndex(entries: entries)
        return index.directChildren(in: directoryPath, includeAuxiliary: includeAuxiliary)
    }

    public struct DirectChildrenIndex: Sendable {
        public let entryCount: Int
        private let allChildrenByParent: [String: [ArchiveEntry]]

        public init(entries: [ArchiveEntry]) {
            self.entryCount = entries.count
            var byParent: [String: [String: ArchiveEntry]] = [:]

            for entry in entries {
                let cleanPath = ArchiveBrowserProjection.canonicalDirectoryPath(entry.path)
                guard !cleanPath.isEmpty else { continue }
                let components = cleanPath.split(separator: "/").map(String.init)

                // Synthesize virtual ancestor directories if missing
                if components.count > 1 {
                    for depth in 1..<components.count {
                        let dirPath = components[0..<depth].joined(separator: "/")
                        let parent = depth == 1 ? "" : components[0..<(depth - 1)].joined(separator: "/")
                        if byParent[parent]?[dirPath] == nil {
                            let synthetic = ArchiveEntry(
                                id: dirPath,
                                path: dirPath,
                                type: .directory
                            )
                            byParent[parent, default: [:]][dirPath] = synthetic
                        }
                    }
                }

                let parent = components.count == 1 ? "" : components.dropLast().joined(separator: "/")
                byParent[parent, default: [:]][cleanPath] = entry
            }

            var sortedMap: [String: [ArchiveEntry]] = [:]
            for (parent, dict) in byParent {
                sortedMap[parent] = ArchiveBrowserProjection.sortedForBrowser(Array(dict.values))
            }
            self.allChildrenByParent = sortedMap
        }

        public func directChildren(in directoryPath: String, includeAuxiliary: Bool = false) -> [ArchiveEntry] {
            let canonical = ArchiveBrowserProjection.canonicalDirectoryPath(directoryPath)
            let items = allChildrenByParent[canonical] ?? []
            if includeAuxiliary {
                return items
            }
            return items.filter { !$0.isAuxiliary }
        }
    }
}

// MARK: - Compression & Task Progress Models

public enum ArchiveEncryptionMode: String, Codable, Sendable, Hashable {
    case none
    case aes256
    case zipCrypto
}

public enum CompressionExecutionPolicy: String, Codable, Sendable, Hashable {
    case allAvailable
    case fixed
}

public enum ArchiveCreationSourceMode: String, Codable, Sendable, Hashable {
    case preparedDirect
    case preparedProjection
    case preparedStage
}

public struct CompressionProfile: Codable, Sendable, Hashable {
    public var format: ArchiveFormat
    public var level: Int
    public var solid: Bool
    public var volumeSize: Int64?
    public var encryption: ArchiveEncryptionMode
    public var encryptHeaders: Bool
    public var password: String?
    public var preserveMacMetadata: Bool
    public var pathRemappings: [String: String]

    public init(
        format: ArchiveFormat = .zip,
        level: Int = 6,
        solid: Bool = false,
        volumeSize: Int64? = nil,
        encryption: ArchiveEncryptionMode = .none,
        encryptHeaders: Bool = false,
        password: String? = nil,
        preserveMacMetadata: Bool = false,
        pathRemappings: [String: String] = [:]
    ) {
        self.format = format
        self.level = level
        self.solid = solid
        self.volumeSize = volumeSize
        self.encryption = encryption
        self.encryptHeaders = encryptHeaders
        self.password = password
        self.preserveMacMetadata = preserveMacMetadata
        self.pathRemappings = pathRemappings
    }
}

public enum ArchiveTaskProgressUnit: String, Codable, Sendable, Hashable {
    case bytes
    case percentage
}

public enum ArchiveTaskProgressPhase: String, Codable, Sendable, Hashable {
    case preparing
    case engineProcessing
    case copying
    case finalizing
    case publishing
}

public struct ArchiveTaskProgress: Codable, Sendable, Hashable {
    public let completed: Int64
    public let total: Int64?
    public let message: String
    public let unit: ArchiveTaskProgressUnit
    public let phase: ArchiveTaskProgressPhase

    public init(
        completed: Int64,
        total: Int64?,
        message: String,
        unit: ArchiveTaskProgressUnit = .bytes,
        phase: ArchiveTaskProgressPhase = .engineProcessing
    ) {
        self.completed = completed
        self.total = total
        self.message = message
        self.unit = unit
        self.phase = phase
    }
}

public struct ArchiveCreationResult: Codable, Sendable, Hashable {
    public let primaryURL: URL
    public let memberURLs: [URL]

    public init(primaryURL: URL, memberURLs: [URL]? = nil) {
        self.primaryURL = primaryURL
        self.memberURLs = memberURLs ?? [primaryURL]
    }
}

// MARK: - ArchiveSourceFingerprint

/// File identity fingerprint for cache validation:
/// `(standardizedPath, deviceNumber, fileNumber, byteCount, modificationNanoseconds)`
public struct ArchiveSourceFingerprint: Codable, Sendable, Hashable {
    public let standardizedPath: String
    public let deviceNumber: UInt64
    public let fileNumber: UInt64
    public let byteCount: UInt64
    public let modificationNanoseconds: Int64

    public init(
        standardizedPath: String,
        deviceNumber: UInt64,
        fileNumber: UInt64,
        byteCount: UInt64,
        modificationNanoseconds: Int64
    ) {
        self.standardizedPath = standardizedPath
        self.deviceNumber = deviceNumber
        self.fileNumber = fileNumber
        self.byteCount = byteCount
        self.modificationNanoseconds = modificationNanoseconds
    }

    public static func capture(at url: URL) throws -> ArchiveSourceFingerprint {
        let standardized = url.standardizedFileURL.path
        var st = Darwin.stat()
        guard Darwin.lstat(standardized, &st) == 0 else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: standardized])
        }
        let mtimeNanos = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        return ArchiveSourceFingerprint(
            standardizedPath: standardized,
            deviceNumber: UInt64(bitPattern: Int64(st.st_dev)),
            fileNumber: st.st_ino,
            byteCount: UInt64(max(0, st.st_size)),
            modificationNanoseconds: mtimeNanos
        )
    }
}

// MARK: - ChangeSet

public struct ChangeSet: Codable, Sendable, Hashable {
    public enum Operation: Codable, Sendable, Hashable {
        case add(sourceURL: URL, archivePath: String)
        case replace(sourceURL: URL, archivePath: String)
        case rename(from: String, to: String)
        case delete(archivePath: String)
    }

    public let operations: [Operation]

    public init(operations: [Operation]) {
        self.operations = operations
    }
}
