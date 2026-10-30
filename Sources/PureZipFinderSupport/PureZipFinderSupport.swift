import Foundation
import ArchiveCore

// MARK: - PureZipFinderIntegration

public enum PureZipFinderIntegration {
    public static let URLScheme = "purezip"
    public static let requestHost = "finder-action"
    public static let sharedContainerIdentifier = "group.com.minato.purezip"
    public static let backgroundLaunchArgument = "--finder-background"
    public static let maximumSourceCount = 500
}

// MARK: - FinderActionRequest & Store

public enum FinderActionError: Error, LocalizedError, Sendable, Equatable {
    case emptySelection
    case tooManySources(Int)
    case missingParentDirectory
    case requestExpired
    case invalidLaunchURL

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "No Finder items selected"
        case let .tooManySources(count):
            return "Selection count (\(count)) exceeds maximum (\(PureZipFinderIntegration.maximumSourceCount))"
        case .missingParentDirectory:
            return "Could not determine parent directory for selection"
        case .requestExpired:
            return "Finder action request has expired"
        case .invalidLaunchURL:
            return "Invalid purezip:// launch URL"
        }
    }
}

/// Finder context menu and system service request payload.
public struct FinderActionRequest: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, Equatable, CaseIterable {
        case browseArchive
        case quickZIP
        case quick7Z
        case advancedCompression
        case quickExtractToNamedFolder
        case quickExtractHere
        case quickExtractTo
        case quickExtractBatchToNamedFolders
        case quickExtractBatchHere
        case quickExtractBatchTo
        case testArchive
        case sendToPureZip

        public var isExtraction: Bool {
            switch self {
            case .quickExtractToNamedFolder, .quickExtractHere, .quickExtractTo,
                 .quickExtractBatchToNamedFolders, .quickExtractBatchHere, .quickExtractBatchTo:
                return true
            default:
                return false
            }
        }

        public var isBatchExtraction: Bool {
            switch self {
            case .quickExtractBatchToNamedFolders, .quickExtractBatchHere, .quickExtractBatchTo:
                return true
            default:
                return false
            }
        }

        public var launchesInBackground: Bool {
            switch self {
            case .quickZIP, .quick7Z, .quickExtractToNamedFolder, .quickExtractHere,
                 .quickExtractBatchToNamedFolders, .quickExtractBatchHere:
                return true
            default:
                return false
            }
        }

        public var activatesApplication: Bool {
            !launchesInBackground
        }
    }

    public let id: UUID
    public let action: Action
    public let sources: [URL]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        action: Action,
        sources: [URL],
        createdAt: Date = Date()
    ) throws {
        guard !sources.isEmpty else {
            throw FinderActionError.emptySelection
        }
        guard sources.count <= PureZipFinderIntegration.maximumSourceCount else {
            throw FinderActionError.tooManySources(sources.count)
        }
        self.id = id
        self.action = action
        self.sources = sources.map(\.standardizedFileURL)
        self.createdAt = createdAt
    }
}

public struct FinderActionLaunchReference: Sendable, Equatable {
    public let requestID: UUID
    public let requestFileURL: URL

    public init(requestID: UUID, requestFileURL: URL) {
        self.requestID = requestID
        self.requestFileURL = requestFileURL
    }
}

public enum FinderActionLaunchURL {
    public static func make(requestID: UUID, requestFileURL: URL) -> URL {
        var comps = URLComponents()
        comps.scheme = PureZipFinderIntegration.URLScheme
        comps.host = PureZipFinderIntegration.requestHost
        comps.queryItems = [
            URLQueryItem(name: "id", value: requestID.uuidString),
            URLQueryItem(name: "file", value: requestFileURL.path)
        ]
        return comps.url!
    }

    public static func reference(from url: URL) -> FinderActionLaunchReference? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.scheme == PureZipFinderIntegration.URLScheme,
              comps.host == PureZipFinderIntegration.requestHost,
              let items = comps.queryItems,
              let idStr = items.first(where: { $0.name == "id" })?.value,
              let reqID = UUID(uuidString: idStr),
              let filePath = items.first(where: { $0.name == "file" })?.value,
              !filePath.isEmpty else {
            return nil
        }
        return FinderActionLaunchReference(
            requestID: reqID,
            requestFileURL: URL(fileURLWithPath: filePath)
        )
    }
}

public struct FinderActionRequestStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("com.minato.purezip.finder-requests", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    public func write(_ request: FinderActionRequest) throws -> URL {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let fileURL = rootDirectory.appendingPathComponent("request-\(request.id.uuidString).json")
        let data = try JSONEncoder().encode(request)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func consume(
        _ reference: FinderActionLaunchReference,
        now: Date = Date(),
        maximumAge: TimeInterval = 120
    ) throws -> FinderActionRequest {
        defer { remove(reference.requestFileURL) }
        let data = try Data(contentsOf: reference.requestFileURL)
        let request = try JSONDecoder().decode(FinderActionRequest.self, from: data)
        guard request.id == reference.requestID,
              now.timeIntervalSince(request.createdAt) <= maximumAge else {
            throw FinderActionError.requestExpired
        }
        return request
    }

    public func remove(_ requestFileURL: URL) {
        try? FileManager.default.removeItem(at: requestFileURL)
    }
}

// MARK: - FinderArchiveNaming

public enum FinderArchiveNaming {
    public static func suggestedStem(for sources: [URL]) -> String {
        guard let first = sources.first else { return "Archive" }
        if sources.count == 1 {
            let name = first.lastPathComponent
            let (stem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(name)
            return stem.isEmpty ? "Archive" : stem
        }
        let parentName = first.deletingLastPathComponent().lastPathComponent
        return (parentName.isEmpty || parentName == "/") ? "Archive" : parentName
    }

    public static func availableZIPDestination(
        for sources: [URL],
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let first = sources.first else {
            throw FinderActionError.emptySelection
        }
        let parent = first.deletingLastPathComponent()
        let stem = suggestedStem(for: sources)
        let proposed = parent.appendingPathComponent("\(stem).zip")
        return ArchiveOutputFamily.collisionFreeBaseURL(for: proposed, fileManager: fileManager)
    }

    public static func publishStagedArchive(_ stagedURL: URL, proposed: URL) throws -> URL {
        let fm = FileManager.default
        let finalURL = ArchiveOutputFamily.collisionFreeBaseURL(for: proposed, fileManager: fm)
        try fm.moveItem(at: stagedURL, to: finalURL)
        return finalURL
    }
}

// MARK: - DestinationCollisionIndex

/// Tracks existing and newly-reserved destination file/directory names during extraction publishing.
public struct DestinationCollisionIndex: @unchecked Sendable {
    public private(set) var directoryEnumerationCount: Int = 0
    private var snapshotsByDirectory: [String: Set<String>] = [:]
    private var reservedConflictKeys: Set<String> = []
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public mutating func existingItem(named name: String, in directory: URL) throws -> URL? {
        let dirKey = directory.standardizedFileURL.path
        if snapshotsByDirectory[dirKey] == nil {
            let names = (try? fileManager.contentsOfDirectory(atPath: dirKey)) ?? []
            snapshotsByDirectory[dirKey] = Set(names.map { $0.lowercased() })
            directoryEnumerationCount += 1
        }
        let lowerName = name.lowercased()
        let fullCandidate = directory.appendingPathComponent(name)
        let conflictKey = "\(dirKey)/\(lowerName)"
        if snapshotsByDirectory[dirKey]?.contains(lowerName) == true ||
           reservedConflictKeys.contains(conflictKey) ||
           fileManager.fileExists(atPath: fullCandidate.path) {
            return fullCandidate
        }
        return nil
    }

    public mutating func reserve(_ url: URL) {
        let std = url.standardizedFileURL
        let dirKey = std.deletingLastPathComponent().path
        let lowerName = std.lastPathComponent.lowercased()
        snapshotsByDirectory[dirKey, default: []].insert(lowerName)
        reservedConflictKeys.insert("\(dirKey)/\(lowerName)")
    }

    public mutating func invalidate(_ directory: URL) {
        let dirKey = directory.standardizedFileURL.path
        snapshotsByDirectory.removeValue(forKey: dirKey)
    }

    public mutating func collisionFreeDestination(for proposedURL: URL) throws -> URL {
        let dir = proposedURL.deletingLastPathComponent()
        let name = proposedURL.lastPathComponent
        if try existingItem(named: name, in: dir) == nil {
            reserve(proposedURL)
            return proposedURL
        }

        let (stem, ext) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(name)
        for idx in 2...10_000 {
            let candidateName = "\(stem) \(idx)\(ext)"
            if try existingItem(named: candidateName, in: dir) == nil {
                let candidateURL = dir.appendingPathComponent(candidateName)
                reserve(candidateURL)
                return candidateURL
            }
        }
        let fallback = dir.appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(8))\(ext)")
        reserve(fallback)
        return fallback
    }
}

// MARK: - ExtractionFinalizationManifest

/// Inspects a staged extraction directory, filters macOS metadata noise (`__MACOSX`, `.DS_Store`, `._*`)
/// outside atomic packages while preserving atomic packages (`.app`, `.framework`, `.rtfd`, `.bundle`).
public struct ExtractionFinalizationManifest: Sendable {

    public enum NodeKind: String, Codable, Sendable, Equatable {
        case file
        case directory
        case symbolicLink
    }

    public struct FilterCandidate: Sendable, Equatable {
        public let url: URL
        public let name: String
        public let relativePath: String
        public let kind: NodeKind
        public let symbolicLinkTarget: String?
        public let isInsideAtomicPackage: Bool
        public let atomicPackageRootRelativePath: String?
    }

    public struct Node: Sendable, Equatable {
        public let sourceURL: URL
        public let name: String
        public let relativePath: String
        public let kind: NodeKind
    }

    private static let atomicPackageExtensions: Set<String> = [
        "app", "framework", "rtfd", "bundle", "plugin", "qlgenerator", "appex", "xpc"
    ]

    public let stagingDirectory: URL
    public let topLevelNodes: [Node]
    public let totalNodeCount: Int
    public let filteredItemCount: Int
    public let totalRegularFileBytes: Int64

    public var isEmpty: Bool {
        topLevelNodes.isEmpty
    }

    public static func prepare(
        stagingDirectory: URL,
        fileManager: FileManager = .default,
        shouldRemove: ((FilterCandidate) throws -> Bool)? = nil
    ) throws -> ExtractionFinalizationManifest {
        let stdStaging = stagingDirectory.standardizedFileURL
        let rootPrefix = stdStaging.path.hasSuffix("/") ? stdStaging.path : stdStaging.path + "/"

        let defaultFilter: (FilterCandidate) -> Bool = { candidate in
            // Never strip files inside an atomic bundle (e.g. `MyApp.app/Contents/...`)
            if candidate.isInsideAtomicPackage {
                return false
            }
            let comps = candidate.relativePath.split(separator: "/")
            if comps.contains("__MACOSX") {
                return true
            }
            if candidate.name == ".DS_Store" || candidate.name.hasPrefix("._") {
                return true
            }
            return false
        }

        var filteredCount = 0
        var urlsToRemove: [URL] = []

        if let enumerator = fileManager.enumerator(
            at: stdStaging,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) {
            for case let itemURL as URL in enumerator {
                let stdItem = itemURL.standardizedFileURL
                guard stdItem.path.hasPrefix(rootPrefix) else { continue }
                let relPath = String(stdItem.path.dropFirst(rootPrefix.count))
                let comps = relPath.split(separator: "/").map(String.init)

                // Check if inside an atomic package ancestor
                var atomicRoot: String?
                if comps.count > 1 {
                    for depth in 0..<(comps.count - 1) {
                        let ext = (comps[depth] as NSString).pathExtension.lowercased()
                        if atomicPackageExtensions.contains(ext) {
                            atomicRoot = comps[0...depth].joined(separator: "/")
                            break
                        }
                    }
                }

                let vals = try? stdItem.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let kind: NodeKind
                var symTarget: String?
                if vals?.isSymbolicLink == true {
                    kind = .symbolicLink
                    symTarget = try? fileManager.destinationOfSymbolicLink(atPath: stdItem.path)
                } else if vals?.isDirectory == true {
                    kind = .directory
                } else {
                    kind = .file
                }

                let candidate = FilterCandidate(
                    url: stdItem,
                    name: stdItem.lastPathComponent,
                    relativePath: relPath,
                    kind: kind,
                    symbolicLinkTarget: symTarget,
                    isInsideAtomicPackage: atomicRoot != nil,
                    atomicPackageRootRelativePath: atomicRoot
                )

                let remove = try shouldRemove?(candidate) ?? defaultFilter(candidate)
                if remove {
                    urlsToRemove.append(stdItem)
                    filteredCount += 1
                    if kind == .directory {
                        enumerator.skipDescendants()
                    }
                }
            }
        }

        for url in urlsToRemove {
            try? fileManager.removeItem(at: url)
        }

        // Recount remaining nodes & top-level nodes
        var totalNodes = 0
        var totalBytes: Int64 = 0
        if let enumerator = fileManager.enumerator(
            at: stdStaging,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) {
            for case let itemURL as URL in enumerator {
                totalNodes += 1
                if let vals = try? itemURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   vals.isRegularFile == true,
                   let sz = vals.fileSize {
                    totalBytes += Int64(sz)
                }
            }
        }

        let topURLs = (try? fileManager.contentsOfDirectory(
            at: stdStaging,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )) ?? []

        let topNodes: [Node] = topURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let std = url.standardizedFileURL
            let vals = try? std.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let kind: NodeKind
            if vals?.isSymbolicLink == true {
                kind = .symbolicLink
            } else if vals?.isDirectory == true {
                kind = .directory
            } else {
                kind = .file
            }
            return Node(
                sourceURL: std,
                name: std.lastPathComponent,
                relativePath: std.lastPathComponent,
                kind: kind
            )
        }

        return ExtractionFinalizationManifest(
            stagingDirectory: stdStaging,
            topLevelNodes: topNodes,
            totalNodeCount: totalNodes,
            filteredItemCount: filteredCount,
            totalRegularFileBytes: totalBytes
        )
    }
}

// MARK: - FinderExtractionPublisher

/// Publishes staged extraction results into the user's destination directory.
public enum FinderExtractionPublisher {

    public enum DirectoryConflictPolicy: String, Codable, Sendable, Hashable {
        case rename
        case merge
        case replace
    }

    public struct ExtractionConflictReport: Sendable, Equatable {
        public let directoryNames: [String]
        public var requiresDecision: Bool { !directoryNames.isEmpty }

        public init(directoryNames: [String]) {
            self.directoryNames = directoryNames
        }
    }

    public static func conflictReport(
        using manifest: ExtractionFinalizationManifest,
        in destination: URL,
        collisionIndex: inout DestinationCollisionIndex,
        fileManager: FileManager = .default
    ) throws -> ExtractionConflictReport {
        var conflicts: [String] = []
        for node in manifest.topLevelNodes where node.kind == .directory {
            if let existing = try collisionIndex.existingItem(named: node.name, in: destination) {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: existing.path, isDirectory: &isDir), isDir.boolValue {
                    conflicts.append(node.name)
                }
            }
        }
        return ExtractionConflictReport(directoryNames: conflicts)
    }

    /// Smart extraction publishing:
    /// - If the manifest has a single top-level item, moves that single item directly into `destination`
    ///   (avoiding double-nested folders).
    /// - If the manifest has multiple top-level items and `enclosingFolderName` is provided, wraps them
    ///   in a collision-free folder named `enclosingFolderName`.
    /// - Otherwise moves/merges each top-level item according to `directoryConflictPolicy`.
    public static func publishMergingContents(
        using manifest: ExtractionFinalizationManifest,
        to destination: URL,
        collisionIndex: inout DestinationCollisionIndex,
        fileManager: FileManager = .default,
        directoryConflictPolicy: DirectoryConflictPolicy = .rename
    ) throws -> [URL] {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        var publishedURLs: [URL] = []

        for node in manifest.topLevelNodes {
            let proposed = destination.appendingPathComponent(node.name)

            if node.kind == .directory,
               try collisionIndex.existingItem(named: node.name, in: destination) != nil {
                switch directoryConflictPolicy {
                case .rename:
                    let freeURL = try collisionIndex.collisionFreeDestination(for: proposed)
                    try fileManager.moveItem(at: node.sourceURL, to: freeURL)
                    publishedURLs.append(freeURL)
                case .replace:
                    if fileManager.fileExists(atPath: proposed.path) {
                        try fileManager.removeItem(at: proposed)
                    }
                    try fileManager.moveItem(at: node.sourceURL, to: proposed)
                    collisionIndex.reserve(proposed)
                    publishedURLs.append(proposed)
                case .merge:
                    try mergeDirectory(from: node.sourceURL, into: proposed, collisionIndex: &collisionIndex, fileManager: fileManager)
                    publishedURLs.append(proposed)
                }
            } else {
                let freeURL = try collisionIndex.collisionFreeDestination(for: proposed)
                try fileManager.moveItem(at: node.sourceURL, to: freeURL)
                publishedURLs.append(freeURL)
            }
        }
        return publishedURLs
    }

    public static func publishDirectory(
        using manifest: ExtractionFinalizationManifest,
        named directoryName: String,
        to destinationParent: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        var collisionIndex = DestinationCollisionIndex(fileManager: fileManager)

        // Single top-level root item -> publish directly without double-wrapping
        if manifest.topLevelNodes.count == 1, let single = manifest.topLevelNodes.first {
            let proposed = destinationParent.appendingPathComponent(single.name)
            let finalURL = try collisionIndex.collisionFreeDestination(for: proposed)
            try fileManager.moveItem(at: single.sourceURL, to: finalURL)
            return finalURL
        }

        // Multiple top-level items -> wrap in a folder named `directoryName`
        let proposedWrapper = destinationParent.appendingPathComponent(directoryName)
        let wrapperURL = try collisionIndex.collisionFreeDestination(for: proposedWrapper)
        try fileManager.createDirectory(at: wrapperURL, withIntermediateDirectories: true)
        for node in manifest.topLevelNodes {
            let dest = wrapperURL.appendingPathComponent(node.name)
            try fileManager.moveItem(at: node.sourceURL, to: dest)
        }
        return wrapperURL
    }

    private static func mergeDirectory(
        from sourceDir: URL,
        into targetDir: URL,
        collisionIndex: inout DestinationCollisionIndex,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey])
        for child in children {
            let name = child.lastPathComponent
            let destChild = targetDir.appendingPathComponent(name)
            var isChildDir: ObjCBool = false
            var isDestDir: ObjCBool = false
            let childExists = fileManager.fileExists(atPath: child.path, isDirectory: &isChildDir)
            let destExists = fileManager.fileExists(atPath: destChild.path, isDirectory: &isDestDir)

            if childExists && destExists && isChildDir.boolValue && isDestDir.boolValue {
                try mergeDirectory(from: child, into: destChild, collisionIndex: &collisionIndex, fileManager: fileManager)
            } else {
                let freeURL = try collisionIndex.collisionFreeDestination(for: destChild)
                try fileManager.moveItem(at: child, to: freeURL)
            }
        }
    }
}
