import Foundation
import ArchiveCore

/// Wrapper for the `7zz` command-line tool and technical catalog reader.
/// Automatically locates `/Applications/PureZip.app/Contents/Resources/7zz`, `/opt/homebrew/bin/7zz`,
/// or `/usr/local/bin/7zz`.
public struct SevenZipEngine: ArchiveEngine {
    public let id: String = "sevenZip"
    public let supportedFormats: Set<ArchiveFormat> = [
        .sevenZip, .rar, .zip, .tar, .gzip, .bzip2, .xz, .lzma,
        .iso, .cab, .arj, .cpio, .rpm, .lha, .msi, .exe, .cbr
    ]
    public let executableURL: URL?

    public init(executableURL: URL? = nil) {
        if let provided = executableURL {
            self.executableURL = provided
        } else {
            let candidates: [String?] = [
                Bundle.main.url(forResource: "7zz", withExtension: nil)?.path,
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/7zz").path,
                "/Applications/PureZip.app/Contents/Resources/7zz",
                "/opt/homebrew/bin/7zz",
                "/usr/local/bin/7zz",
                "/usr/bin/7zz"
            ]
            self.executableURL = candidates
                .compactMap { $0 }
                .map { URL(fileURLWithPath: $0) }
                .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }
    }

    public var isAvailable: Bool {
        guard let url = executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilitySet {
        switch format {
        case .sevenZip, .zip:
            return [.list, .extract, .create, .update, .encrypt, .test, .splitVolumes]
        case .rar:
            return [.list, .extract, .test, .splitVolumes]
        case .tar, .gzip, .bzip2, .xz:
            return [.list, .extract, .create, .test]
        default:
            return supportedFormats.contains(format) ? [.list, .extract, .test] : []
        }
    }

    public func probe(_ url: URL) async throws -> ArchiveFormatDescriptor? {
        let desc = ArchiveFormatDescriptor.detect(at: url)
        return supportedFormats.contains(desc.format) ? desc : nil
    }

    // MARK: - CatalogReader (`7zz l -slt` Parser)

    /// Technical catalog parser for `7zz` output in `PureZipArchiveService`.
    /// Parses `7zz l -slt` output, including multiline archive comments (`Comment = \n{\n...\n}`),
    /// `----------` separator blocks, and per-entry key-value properties.
    public struct CatalogReader: Sendable {
        public struct ParsedCatalog: Sendable {
            public let entries: [ArchiveEntry]
            public let archiveComment: String?
        }

        public static func parse(sltOutput: String, archiveRootName: String? = nil) -> ParsedCatalog {
            let lines = sltOutput.components(separatedBy: .newlines)
            let hasTenHyphenSeparator = lines.contains { $0.hasPrefix("----------") }
            var inEntriesSection = false
            var inMultilineComment = false
            var commentLines: [String] = []
            var archiveComment: String?

            var currentFields: [String: String] = [:]
            var entries: [ArchiveEntry] = []

            func flushRecord() {
                guard !currentFields.isEmpty else { return }
                defer { currentFields.removeAll(keepingCapacity: true) }
                guard let rawPath = currentFields["Path"], !rawPath.isEmpty else { return }
                if let rootName = archiveRootName, rawPath == rootName {
                    return
                }

                let isFolder = currentFields["Folder"] == "+"
                let attrs = currentFields["Attributes"] ?? ""
                let mode = currentFields["Mode"] ?? ""
                let symTarget = currentFields["Symbolic Link"]
                let isDir = isFolder || attrs.hasPrefix("D") || attrs.contains("d") || mode.hasPrefix("d")
                let isSymlink = (symTarget != nil && !symTarget!.isEmpty) || attrs.hasPrefix("l") || mode.hasPrefix("l")

                let entryType: ArchiveEntryType
                if isSymlink {
                    entryType = .symbolicLink
                } else if isDir {
                    entryType = .directory
                } else {
                    entryType = .file
                }

                let uncomp = Int64(currentFields["Size"] ?? "") ?? 0
                let comp = Int64(currentFields["Packed Size"] ?? "") ?? uncomp
                let encrypted = currentFields["Encrypted"] == "+"
                let crcHex = currentFields["CRC"]
                let crc = crcHex.flatMap { UInt32($0, radix: 16) }
                let modDate = parseTimestamp(currentFields["Modified"])

                let entry = ArchiveEntry(
                    id: ArchiveBrowserProjection.canonicalEntryPath(rawPath, isDirectory: entryType == .directory),
                    path: rawPath,
                    type: entryType,
                    uncompressedSize: uncomp,
                    compressedSize: comp,
                    modifiedAt: modDate,
                    checksum: crc,
                    encrypted: encrypted,
                    linkTarget: symTarget
                )
                if !entry.path.isEmpty {
                    entries.append(entry)
                }
            }

            for line in lines {
                if !inEntriesSection {
                    if line.hasPrefix("----------") {
                        inEntriesSection = true
                        inMultilineComment = false
                        if !commentLines.isEmpty {
                            archiveComment = commentLines.joined(separator: "\n")
                        }
                        continue
                    }
                    if inMultilineComment {
                        if line == "}" {
                            inMultilineComment = false
                            archiveComment = commentLines.joined(separator: "\n")
                        } else if line != "{" {
                            commentLines.append(line)
                        }
                        continue
                    }
                    if line.hasPrefix("Comment =") {
                        let remainder = String(line.dropFirst("Comment =".count)).trimmingCharacters(in: .whitespaces)
                        if remainder == "{" || remainder.isEmpty {
                            inMultilineComment = true
                        } else {
                            archiveComment = remainder
                        }
                        continue
                    }
                    // Fallback only when the entire output has no `----------` banner
                    if !hasTenHyphenSeparator && line.hasPrefix("Path = ") {
                        let candidatePath = String(line.dropFirst("Path = ".count)).trimmingCharacters(in: .whitespaces)
                        if archiveRootName == nil || candidatePath != archiveRootName {
                            inEntriesSection = true
                            inMultilineComment = false
                            if !commentLines.isEmpty {
                                archiveComment = commentLines.joined(separator: "\n")
                            }
                            currentFields["Path"] = candidatePath
                            continue
                        }
                    }
                    continue
                }

                // Inside `----------` entries section
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushRecord()
                    continue
                }
                if let eqRange = line.range(of: " = ") {
                    let key = String(line[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let val = String(line[eqRange.upperBound...])
                    currentFields[key] = val
                }
            }
            flushRecord()

            return ParsedCatalog(entries: entries, archiveComment: archiveComment)
        }

        private static func parseTimestamp(_ str: String?) -> Date? {
            guard let s = str, s.count >= 19 else { return nil }
            let bytes = Array(s.utf8.prefix(19))
            guard bytes.count == 19 else { return nil }
            // Expected format: YYYY-MM-DD HH:MM:SS
            guard bytes[4] == 45, bytes[7] == 45, (bytes[10] == 32 || bytes[10] == 84), bytes[13] == 58, bytes[16] == 58 else {
                return nil
            }
            func parse2(_ o: Int) -> Int? {
                let d1 = Int(bytes[o]) - 48
                let d2 = Int(bytes[o + 1]) - 48
                guard d1 >= 0, d1 <= 9, d2 >= 0, d2 <= 9 else { return nil }
                return d1 * 10 + d2
            }
            func parse4(_ o: Int) -> Int? {
                guard let hi = parse2(o), let lo = parse2(o + 2) else { return nil }
                return hi * 100 + lo
            }
            guard let y = parse4(0),
                  let m = parse2(5),
                  let d = parse2(8),
                  let hr = parse2(11),
                  let min = parse2(14),
                  let sec = parse2(17) else {
                return nil
            }
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            comps.hour = hr
            comps.minute = min
            comps.second = sec
            comps.timeZone = TimeZone(secondsFromGMT: 0)
            return Calendar(identifier: .gregorian).date(from: comps)
        }
    }

    // MARK: - ArchiveEngine Operations

    public func list(_ url: URL, password: String? = nil) -> AsyncThrowingStream<[ArchiveEntry], Error> {
        AsyncThrowingStream { continuation in
            do {
                guard let bin = executableURL else {
                    throw ArchiveEngineError.engineFailure(backend: id, detail: "7zz binary not found")
                }
                let primary = ArchiveVolumeFamily.primaryURL(for: url)
                var args = ["l", "-slt"]
                if let pw = password, !pw.isEmpty {
                    args.append("-p\(pw)")
                } else {
                    args.append("-p")
                }
                args.append(primary.path)

                let output = try Self.runProcess(executable: bin, arguments: args)
                let parsed = CatalogReader.parse(sltOutput: output, archiveRootName: primary.lastPathComponent)
                continuation.yield(parsed.entries)
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
        guard let bin = executableURL else {
            throw ArchiveEngineError.engineFailure(backend: id, detail: "7zz binary not found")
        }
        for entry in entries {
            _ = try Self.validatedDestinationURL(for: entry.path, inside: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        var args = ["x", "-y", "-o\(destination.path)"]
        if let pw = password, !pw.isEmpty {
            args.append("-p\(pw)")
        } else {
            args.append("-p")
        }
        args.append(primary.path)
        for entry in entries {
            args.append(entry.path)
        }

        progress?(ArchiveTaskProgress(completed: 0, total: 100, message: primary.lastPathComponent, unit: .percentage, phase: .engineProcessing))
        _ = try Self.runProcess(executable: bin, arguments: args)
        progress?(ArchiveTaskProgress(completed: 100, total: 100, message: primary.lastPathComponent, unit: .percentage, phase: .finalizing))
    }

    public func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile = CompressionProfile(format: .sevenZip),
        sourceMode: ArchiveCreationSourceMode = .preparedDirect,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        guard let bin = executableURL else {
            throw ArchiveEngineError.engineFailure(backend: id, detail: "7zz binary not found")
        }
        var args = ["a", "-y", "-mx=\(max(0, min(9, profile.level)))"]
        if profile.format == .sevenZip {
            args.append("-t7z")
            args.append(profile.solid ? "-ms=on" : "-ms=off")
        } else if profile.format == .zip {
            args.append("-tzip")
            args.append("-mcu=on")
        }
        if let pw = profile.password, !pw.isEmpty {
            args.append("-p\(pw)")
            if profile.encryptHeaders && profile.format == .sevenZip {
                args.append("-mhe=on")
            }
        }
        if let volBytes = profile.volumeSize, volBytes > 0 {
            args.append("-v\(volBytes)b")
        }
        if !profile.preserveMacMetadata {
            args.append(contentsOf: [
                "-xr!*.DS_Store",
                "-xr!__MACOSX",
                "-xr!._*",
                "-xr!.AppleDouble",
                "-xr!*.AppleDouble"
            ])
        }
        args.append(destination.path)
        args.append(contentsOf: sources.map(\.path))

        progress?(ArchiveTaskProgress(completed: 0, total: 100, message: destination.lastPathComponent, unit: .percentage, phase: .engineProcessing))
        _ = try Self.runProcess(executable: bin, arguments: args)

        // Apply path remappings in-archive if provided (keeps source files on disk untouched)
        if !profile.pathRemappings.isEmpty {
            for (oldPath, newPath) in profile.pathRemappings where oldPath != newPath {
                _ = try? Self.runProcess(executable: bin, arguments: ["rn", "-y", destination.path, oldPath, newPath])
            }
        }

        progress?(ArchiveTaskProgress(completed: 100, total: 100, message: destination.lastPathComponent, unit: .percentage, phase: .finalizing))
    }

    public func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile = CompressionProfile(format: .sevenZip),
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        guard let bin = executableURL else {
            throw ArchiveEngineError.engineFailure(backend: id, detail: "7zz binary not found")
        }
        let fm = FileManager.default
        for op in changes.operations {
            switch op {
            case let .add(sourceURL, archivePath), let .replace(sourceURL, archivePath):
                let stageDir = fm.temporaryDirectory.appendingPathComponent("PureZip7zStage-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: stageDir) }

                let cleanRel = archivePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let targetURL = stageDir.appendingPathComponent(cleanRel)
                try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                var isDir: ObjCBool = false
                if fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir) {
                    try fm.copyItem(at: sourceURL, to: targetURL)
                    var args = ["a", "-y"]
                    if isDir.boolValue {
                        args.append("-r")
                    }
                    args.append(archiveURL.path)
                    args.append(cleanRel)
                    _ = try Self.runProcess(executable: bin, arguments: args, currentDirectoryURL: stageDir)
                }
            case let .delete(archivePath):
                _ = try Self.runProcess(executable: bin, arguments: ["d", "-y", archiveURL.path, archivePath])
            case let .rename(from, to):
                _ = try Self.runProcess(executable: bin, arguments: ["rn", "-y", archiveURL.path, from, to])
            }
        }
    }

    public func test(_ url: URL, password: String? = nil) async throws {
        guard let bin = executableURL else {
            throw ArchiveEngineError.engineFailure(backend: id, detail: "7zz binary not found")
        }
        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        var args = ["t"]
        if let pw = password, !pw.isEmpty {
            args.append("-p\(pw)")
        } else {
            args.append("-p")
        }
        args.append(primary.path)
        _ = try Self.runProcess(executable: bin, arguments: args)
    }

    internal static func runProcess(executable: URL, arguments: [String], currentDirectoryURL: URL? = nil) throws -> String {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        if let currentDirectoryURL = currentDirectoryURL {
            proc.currentDirectoryURL = currentDirectoryURL
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        proc.waitUntilExit()
        group.wait()

        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            let combined = (errStr + " " + outStr).lowercased()
            if combined.contains("password") ||
               combined.contains("cannot open encrypted archive") ||
               combined.contains("can not open encrypted archive") ||
               combined.contains("headers error") {
                throw ArchiveEngineError.wrongPassword
            }
            throw ArchiveEngineError.engineFailure(
                backend: "7zz",
                detail: "exit \(proc.terminationStatus): \(errStr.isEmpty ? outStr : errStr)"
            )
        }
        return outStr
    }
}
