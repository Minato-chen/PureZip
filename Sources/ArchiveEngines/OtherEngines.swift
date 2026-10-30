import Foundation
import ArchiveCore

// MARK: - CompressedStreamEngine

/// Handles single-file compressed streams (`.gz`, `.bz2`, `.xz`, `.lzma`).
public struct CompressedStreamEngine: ArchiveEngine {
    public let id: String = "compressedStream"
    public let supportedFormats: Set<ArchiveFormat> = [.gzip, .bzip2, .xz, .lzma]

    public init() {}

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilitySet {
        guard supportedFormats.contains(format) else { return [] }
        return [.list, .extract, .create, .test]
    }

    public func probe(_ url: URL) async throws -> ArchiveFormatDescriptor? {
        let lower = url.lastPathComponent.lowercased()
        // Compound tar archives belong to BSDTarEngine, not single-stream engine
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") ||
           lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz2") ||
           lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") {
            return nil
        }
        let desc = ArchiveFormatDescriptor.detect(at: url)
        return supportedFormats.contains(desc.format) ? desc : nil
    }

    public static func decompressedEntryName(for url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for suffix in [".gz", ".gzip", ".bz2", ".bzip2", ".xz", ".lzma", ".lz"] {
            if lower.hasSuffix(suffix) && name.count > suffix.count {
                return String(name.dropLast(suffix.count))
            }
        }
        return name + ".out"
    }

    public func list(_ url: URL, password: String? = nil) -> AsyncThrowingStream<[ArchiveEntry], Error> {
        AsyncThrowingStream { continuation in
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let entryName = Self.decompressedEntryName(for: url)
            let entry = ArchiveEntry(
                id: entryName,
                path: entryName,
                type: .file,
                uncompressedSize: fileSize,
                compressedSize: fileSize,
                modifiedAt: modDate
            )
            continuation.yield([entry])
            continuation.finish()
        }
    }

    public func extract(
        _ url: URL,
        entries: [ArchiveEntry],
        to destination: URL,
        password: String? = nil,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let outName = Self.decompressedEntryName(for: url)
        let outURL = try Self.validatedDestinationURL(for: outName, inside: destination)

        let desc = ArchiveFormatDescriptor.detect(at: url)
        let toolPath: String
        switch desc.format {
        case .gzip:
            toolPath = "/usr/bin/gzip"
        case .bzip2:
            toolPath = "/usr/bin/bzip2"
        default:
            // Fallback to 7zz if xz/lzma
            let sevenZip = SevenZipEngine()
            if sevenZip.isAvailable {
                try await sevenZip.extract(url, entries: [], to: destination, password: password, progress: progress)
                return
            }
            throw ArchiveEngineError.unsupportedFormat(url.path)
        }

        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        let outFileHandle = try FileHandle(forWritingTo: outURL)
        defer { try? outFileHandle.close() }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: toolPath)
        proc.arguments = ["-dc", url.path]
        proc.standardOutput = outFileHandle
        let errPipe = Pipe()
        proc.standardError = errPipe

        try proc.run()
        let errReadTask = Task.detached {
            errPipe.fileHandleForReading.readDataToEndOfFile()
        }
        proc.waitUntilExit()
        let errData = await errReadTask.value

        guard proc.terminationStatus == 0 else {
            let err = String(data: errData, encoding: .utf8) ?? ""
            try? FileManager.default.removeItem(at: outURL)
            throw ArchiveEngineError.engineFailure(backend: id, detail: "\(toolPath) exit \(proc.terminationStatus): \(err)")
        }
    }

    public func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile,
        sourceMode: ArchiveCreationSourceMode = .preparedDirect,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        guard let first = sources.first else {
            throw ArchiveEngineError.io("No source file provided for stream compression")
        }
        let toolPath = profile.format == .bzip2 ? "/usr/bin/bzip2" : "/usr/bin/gzip"

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let outFileHandle = try FileHandle(forWritingTo: destination)
        defer { try? outFileHandle.close() }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: toolPath)
        proc.arguments = ["-c", "-\(max(1, min(9, profile.level)))", first.path]
        proc.standardOutput = outFileHandle
        let errPipe = Pipe()
        proc.standardError = errPipe

        try proc.run()
        let errReadTask = Task.detached {
            errPipe.fileHandleForReading.readDataToEndOfFile()
        }
        proc.waitUntilExit()
        let errData = await errReadTask.value

        guard proc.terminationStatus == 0 else {
            let err = String(data: errData, encoding: .utf8) ?? ""
            try? FileManager.default.removeItem(at: destination)
            throw ArchiveEngineError.engineFailure(backend: id, detail: "\(toolPath) exit \(proc.terminationStatus): \(err)")
        }
    }

    public func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        throw ArchiveEngineError.unsupportedCapability(profile.format, .update)
    }

    public func test(_ url: URL, password: String? = nil) async throws {
        let desc = ArchiveFormatDescriptor.detect(at: url)
        let toolPath = desc.format == .bzip2 ? "/usr/bin/bzip2" : "/usr/bin/gzip"
        _ = try SevenZipEngine.runProcess(
            executable: URL(fileURLWithPath: toolPath),
            arguments: ["-t", url.path]
        )
    }
}

// MARK: - LzipEngine

/// Handles `.lz` / `.tlz` lzip archives.
public struct LzipEngine: ArchiveEngine {
    public let id: String = "lzip"
    public let supportedFormats: Set<ArchiveFormat> = [.lzip]

    public init() {}

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilitySet {
        format == .lzip ? [.list, .extract, .create, .test] : []
    }

    public func probe(_ url: URL) async throws -> ArchiveFormatDescriptor? {
        let desc = ArchiveFormatDescriptor.detect(at: url)
        return desc.format == .lzip ? desc : nil
    }

    public func list(_ url: URL, password: String? = nil) -> AsyncThrowingStream<[ArchiveEntry], Error> {
        BSDTarEngine().list(url, password: password)
    }

    public func extract(
        _ url: URL,
        entries: [ArchiveEntry],
        to destination: URL,
        password: String? = nil,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        try await BSDTarEngine().extract(url, entries: entries, to: destination, password: password, progress: progress)
    }

    public func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile,
        sourceMode: ArchiveCreationSourceMode = .preparedDirect,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        try await BSDTarEngine().create(sources: sources, at: destination, profile: profile, sourceMode: sourceMode, progress: progress)
    }

    public func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        throw ArchiveEngineError.unsupportedCapability(.lzip, .update)
    }

    public func test(_ url: URL, password: String? = nil) async throws {
        try await BSDTarEngine().test(url, password: password)
    }
}

// MARK: - DiskImagePresentation & DiskImageEngine

public struct DiskImagePresentation: Codable, Sendable, Hashable {
    public let rootEntries: [ArchiveEntry]
    public let applicationBundleEntries: [ArchiveEntry]
    public let hasApplicationsShortcut: Bool

    public init(
        rootEntries: [ArchiveEntry],
        applicationBundleEntries: [ArchiveEntry],
        hasApplicationsShortcut: Bool
    ) {
        self.rootEntries = rootEntries
        self.applicationBundleEntries = applicationBundleEntries
        self.hasApplicationsShortcut = hasApplicationsShortcut
    }
}

/// Read-only `.dmg` disk image engine using `/usr/bin/hdiutil`.
public struct DiskImageEngine: ArchiveEngine {
    public let id: String = "diskImage"
    public let supportedFormats: Set<ArchiveFormat> = [.dmg]
    public let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/hdiutil")) {
        self.executableURL = executableURL
    }

    /// Automatically detaches / unmounts a DMG disk image or volume mount.
    @discardableResult
    public static func detach(diskImageURL: URL) -> Bool {
        // 1. If path is a direct mountpoint (e.g. /Volumes/... or temporary PureZip_DMG_...), detach it directly first
        var isDir: ObjCBool = false
        if diskImageURL.path.hasPrefix("/Volumes/") ||
            (FileManager.default.fileExists(atPath: diskImageURL.path, isDirectory: &isDir) && isDir.boolValue) {
            let mountPath: String
            if diskImageURL.path.hasPrefix("/Volumes/") {
                let volumeName = diskImageURL.pathComponents.count > 2 ? diskImageURL.pathComponents[2] : ""
                mountPath = "/Volumes/\(volumeName)"
            } else {
                mountPath = diskImageURL.path
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            p.arguments = ["detach", mountPath, "-force"]
            try? p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                return true
            }
        }

        // 2. Query hdiutil info for mounted volumes backed by this image-path
        let output = (try? SevenZipEngine.runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["info"]
        )) ?? ""

        var mountPoints: [String] = []
        let sections = output.components(separatedBy: "================================================")
        for sec in sections {
            if sec.contains(diskImageURL.path) {
                let lines = sec.components(separatedBy: "\n")
                for line in lines {
                    if let r = line.range(of: "/Volumes/") {
                        let mp = String(line[r.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !mountPoints.contains(mp) {
                            mountPoints.append(mp)
                        }
                    }
                }
            }
        }

        for mp in mountPoints {
            let detachP = Process()
            detachP.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachP.arguments = ["detach", mp, "-force"]
            try? detachP.run()
            detachP.waitUntilExit()
        }
        return true
    }

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilitySet {
        format == .dmg ? [.list, .extract, .test] : []
    }

    public func probe(_ url: URL) async throws -> ArchiveFormatDescriptor? {
        let desc = ArchiveFormatDescriptor.detect(at: url)
        return desc.format == .dmg ? desc : nil
    }

    public func presentation(_ url: URL, password: String? = nil) async throws -> DiskImagePresentation {
        var collected: [ArchiveEntry] = []
        for try await batch in list(url, password: password) {
            collected.append(contentsOf: batch)
        }
        let roots = ArchiveBrowserProjection.directChildren(of: collected, in: "", includeAuxiliary: true)
        let apps = roots.filter { $0.path.lowercased().hasSuffix(".app") }
        let hasShortcut = roots.contains { $0.isDMGApplicationsShortcut }
        return DiskImagePresentation(
            rootEntries: roots.filter { !$0.isAuxiliary && !$0.isDiskImageBackground },
            applicationBundleEntries: apps,
            hasApplicationsShortcut: hasShortcut
        )
    }

    public func list(_ url: URL, password: String? = nil) -> AsyncThrowingStream<[ArchiveEntry], Error> {
        let sevenZip = SevenZipEngine()
        if sevenZip.isAvailable {
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        var collected: [ArchiveEntry] = []
                        for try await batch in sevenZip.list(url, password: password) {
                            if !batch.isEmpty {
                                collected.append(contentsOf: batch)
                            }
                        }
                        // Ensure 7zz actually unpacked the inner filesystem and not just raw partition blocks
                        let visibleEntries = collected.filter { !$0.isAuxiliary && !$0.isDiskImageBackground }
                        if !visibleEntries.isEmpty {
                            continuation.yield(collected)
                            continuation.finish()
                            return
                        }
                        try await Self.listViaHDIUtil(url: url, password: password, continuation: continuation)
                    } catch {
                        do {
                            try await Self.listViaHDIUtil(url: url, password: password, continuation: continuation)
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }
        }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Self.listViaHDIUtil(url: url, password: password, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
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
        let sevenZip = SevenZipEngine()
        if sevenZip.isAvailable {
            do {
                try await sevenZip.extract(url, entries: entries, to: destination, password: password, progress: progress)
                let allExtractedExist = entries.isEmpty || entries.allSatisfy { entry in
                    let cleanRel = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard !cleanRel.isEmpty else { return true }
                    return FileManager.default.fileExists(atPath: destination.appendingPathComponent(cleanRel).path)
                }
                if allExtractedExist {
                    return
                }
            } catch {
                // Fall back to native hdiutil extraction
            }
        }
        try await Self.extractViaHDIUtil(url: url, entries: entries, to: destination, password: password, progress: progress)
    }

    private static func listViaHDIUtil(
        url: URL,
        password: String? = nil,
        continuation: AsyncThrowingStream<[ArchiveEntry], Error>.Continuation
    ) async throws {
        let mountDir = FileManager.default.temporaryDirectory.appendingPathComponent("PureZip_DMG_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)
        defer {
            _ = detach(diskImageURL: mountDir)
            try? FileManager.default.removeItem(at: mountDir)
        }

        var args = ["attach", url.path, "-readonly", "-nobrowse", "-mountpoint", mountDir.path]
        if let pw = password, !pw.isEmpty {
            args.append(contentsOf: ["-passphrase", pw])
        }
        _ = try SevenZipEngine.runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: args
        )

        guard let enumerator = FileManager.default.enumerator(
            at: mountDir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey],
            options: []
        ) else {
            continuation.finish()
            return
        }

        var entries: [ArchiveEntry] = []
        let mountPath = mountDir.path

        while let fileURL = enumerator.nextObject() as? URL {
            let fullPath = fileURL.path
            guard fullPath.hasPrefix(mountPath) else { continue }
            let rel = String(fullPath.dropFirst(mountPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !rel.isEmpty else { continue }

            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
            let isDir = values?.isDirectory ?? false
            let isSymlink = values?.isSymbolicLink ?? false
            let size = Int64(values?.fileSize ?? 0)
            let modDate = values?.contentModificationDate
            let symTarget = isSymlink ? (try? FileManager.default.destinationOfSymbolicLink(atPath: fullPath)) : nil

            let entryType: ArchiveEntryType = isSymlink ? .symbolicLink : (isDir ? .directory : .file)

            let entry = ArchiveEntry(
                id: ArchiveBrowserProjection.canonicalEntryPath(rel, isDirectory: entryType == .directory),
                path: rel,
                type: entryType,
                uncompressedSize: size,
                compressedSize: size,
                modifiedAt: modDate,
                linkTarget: symTarget
            )
            entries.append(entry)
        }

        continuation.yield(entries)
        continuation.finish()
    }

    private static func extractViaHDIUtil(
        url: URL,
        entries: [ArchiveEntry],
        to destination: URL,
        password: String? = nil,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        let mountDir = FileManager.default.temporaryDirectory.appendingPathComponent("PureZip_DMG_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)
        defer {
            _ = detach(diskImageURL: mountDir)
            try? FileManager.default.removeItem(at: mountDir)
        }

        var args = ["attach", url.path, "-readonly", "-nobrowse", "-mountpoint", mountDir.path]
        if let pw = password, !pw.isEmpty {
            args.append(contentsOf: ["-passphrase", pw])
        }
        _ = try SevenZipEngine.runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: args
        )

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        if entries.isEmpty {
            let contents = try FileManager.default.contentsOfDirectory(at: mountDir, includingPropertiesForKeys: nil)
            for item in contents {
                let target = try Self.validatedDestinationURL(for: item.lastPathComponent, inside: destination)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: item, to: target)
            }
        } else {
            for entry in entries {
                let target = try Self.validatedDestinationURL(for: entry.path, inside: destination)
                let src = mountDir.appendingPathComponent(entry.path)
                if FileManager.default.fileExists(atPath: src.path) {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try? FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.copyItem(at: src, to: target)
                }
            }
        }
        progress?(ArchiveTaskProgress(completed: 100, total: 100, message: url.lastPathComponent, unit: .percentage, phase: .finalizing))
    }

    public func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile,
        sourceMode: ArchiveCreationSourceMode = .preparedDirect,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        throw ArchiveEngineError.unsupportedCapability(.dmg, .create)
    }

    public func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        throw ArchiveEngineError.unsupportedCapability(.dmg, .update)
    }

    public func test(_ url: URL, password: String? = nil) async throws {
        _ = try SevenZipEngine.runProcess(
            executable: executableURL,
            arguments: ["verify", "-quiet", url.path]
        )
    }
}
