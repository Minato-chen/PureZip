import Foundation
import ArchiveCore

/// Wrapper for system `/usr/bin/bsdtar` (`libarchive`) and catalog reader.
public struct BSDTarEngine: ArchiveEngine {
    public let id: String = "bsdtar"
    public let supportedFormats: Set<ArchiveFormat> = [
        .tar, .gzip, .bzip2, .xz, .iso, .cpio, .pkg, .cab, .lha
    ]
    public let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/bsdtar")) {
        self.executableURL = executableURL
    }

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilitySet {
        switch format {
        case .tar:
            return [.list, .extract, .create, .update, .test]
        case .gzip, .bzip2, .xz, .iso, .cpio, .pkg, .cab, .lha:
            return [.list, .extract, .test]
        default:
            return []
        }
    }

    public func probe(_ url: URL) async throws -> ArchiveFormatDescriptor? {
        let desc = ArchiveFormatDescriptor.detect(at: url)
        return supportedFormats.contains(desc.format) ? desc : nil
    }

    // MARK: - CatalogReader (`bsdtar -tvf` Parser)

    public struct CatalogReader: Sendable {
        public static func parse(verboseOutput: String) -> [ArchiveEntry] {
            var entries: [ArchiveEntry] = []
            for rawLine in verboseOutput.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                if let entry = parseLine(line) {
                    entries.append(entry)
                }
            }
            return entries
        }

        private static func parseLine(_ line: String) -> ArchiveEntry? {
            // Typical `bsdtar -tvf` line on macOS:
            // drwxr-xr-x  0 user staff       0 Oct 24 00:10 folder/
            // -rw-r--r--  0 user staff    1234 Oct 24 00:10 folder/file.txt
            // lrwxr-xr-x  0 user staff       0 Oct 24 00:10 link -> target
            let tokens = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 9 else { return nil }

            let modeStr = tokens[0]
            let sizeVal = Int64(tokens[4]) ?? 0
            var pathPart = tokens[8]
            var linkTarget: String?

            let firstChar = modeStr.first ?? "-"
            let entryType: ArchiveEntryType
            switch firstChar {
            case "d":
                entryType = .directory
            case "l":
                entryType = .symbolicLink
                if let arrowRange = pathPart.range(of: " -> ") {
                    linkTarget = String(pathPart[arrowRange.upperBound...])
                    pathPart = String(pathPart[..<arrowRange.lowerBound])
                }
            case "h":
                entryType = .hardLink
                if let linkRange = pathPart.range(of: " link to ") {
                    linkTarget = String(pathPart[linkRange.upperBound...])
                    pathPart = String(pathPart[..<linkRange.lowerBound])
                }
            default:
                entryType = pathPart.hasSuffix("/") ? .directory : .file
            }

            let perms = parsePermissions(modeStr)
            let canonical = ArchiveBrowserProjection.canonicalEntryPath(pathPart, isDirectory: entryType == .directory)
            guard !canonical.isEmpty else { return nil }

            return ArchiveEntry(
                id: canonical,
                path: canonical,
                type: entryType,
                uncompressedSize: sizeVal,
                compressedSize: sizeVal,
                permissions: perms,
                linkTarget: linkTarget
            )
        }

        private static func parsePermissions(_ mode: String) -> UInt16? {
            let chars = Array(mode)
            guard chars.count >= 10 else { return nil }
            var bits: UInt16 = 0
            let flags: [(Int, Character, UInt16)] = [
                (1, "r", 0o400), (2, "w", 0o200), (3, "x", 0o100),
                (4, "r", 0o040), (5, "w", 0o020), (6, "x", 0o010),
                (7, "r", 0o004), (8, "w", 0o002), (9, "x", 0o001)
            ]
            for (idx, ch, mask) in flags where chars[idx] == ch {
                bits |= mask
            }
            return bits
        }
    }

    // MARK: - ArchiveEngine Conformance

    public func list(_ url: URL, password: String? = nil) -> AsyncThrowingStream<[ArchiveEntry], Error> {
        AsyncThrowingStream { continuation in
            do {
                let output = try SevenZipEngine.runProcess(
                    executable: executableURL,
                    arguments: ["-tvf", url.path]
                )
                let entries = CatalogReader.parse(verboseOutput: output)
                continuation.yield(entries)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func extractWholeArchive(
        _ url: URL,
        to destination: URL,
        password: String? = nil,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        progress?(ArchiveTaskProgress(completed: 0, total: 100, message: url.lastPathComponent, unit: .percentage, phase: .engineProcessing))
        _ = try SevenZipEngine.runProcess(
            executable: executableURL,
            arguments: ["-xf", url.path, "-C", destination.path]
        )
        progress?(ArchiveTaskProgress(completed: 100, total: 100, message: url.lastPathComponent, unit: .percentage, phase: .finalizing))
    }

    public func extract(
        _ url: URL,
        entries: [ArchiveEntry],
        to destination: URL,
        password: String? = nil,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        for entry in entries {
            _ = try Self.validatedDestinationURL(for: entry.path, inside: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var args = ["-xf", url.path, "-C", destination.path]
        args.append(contentsOf: entries.map(\.path))
        _ = try SevenZipEngine.runProcess(executable: executableURL, arguments: args)
    }

    public func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile = CompressionProfile(format: .tar),
        sourceMode: ArchiveCreationSourceMode = .preparedDirect,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lower = destination.lastPathComponent.lowercased()
        var args: [String] = ["-cf"]
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            args = ["-czf", destination.path]
        } else if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz2") {
            args = ["-cjf", destination.path]
        } else if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") {
            args = ["-cJf", destination.path]
        } else {
            args = ["-cf", destination.path]
        }
        if !profile.preserveMacMetadata {
            args.append(contentsOf: [
                "--exclude=*.DS_Store",
                "--exclude=__MACOSX",
                "--exclude=._*",
                "--exclude=.AppleDouble"
            ])
        }
        for src in sources {
            let parent = src.deletingLastPathComponent().path
            args.append(contentsOf: ["-C", parent, src.lastPathComponent])
        }
        _ = try SevenZipEngine.runProcess(executable: executableURL, arguments: args)
    }

    public func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile = CompressionProfile(format: .tar),
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        throw ArchiveEngineError.unsupportedCapability(profile.format, .update)
    }

    public func test(_ url: URL, password: String? = nil) async throws {
        _ = try SevenZipEngine.runProcess(
            executable: executableURL,
            arguments: ["-tf", url.path]
        )
    }
}
