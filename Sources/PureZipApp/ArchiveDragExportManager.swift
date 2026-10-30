import AppKit
import Foundation
import UniformTypeIdentifiers
import ArchiveCore
import ArchiveEngines

/// Coordinates dragging archive entries directly out of PureZip into Finder, Desktop, or other apps
/// using non-blocking file representation promises.
@MainActor
public final class ArchiveDragExportManager {
    public static let shared = ArchiveDragExportManager()

    private let cacheDirectory: URL

    private init() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PureZipDragStaging", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
    }

    /// Creates an `NSItemProvider` configured with file representations for drops to Finder/Desktop.
    /// Crucially avoids registering synchronous `NSURL` promises which cause main-thread hangs in AppKit drag tracking.
    public func itemProvider(for entry: ArchiveEntry, session: ArchiveBrowsingSession) -> NSItemProvider {
        let provider = NSItemProvider()
        let filename = entry.name
        provider.suggestedName = filename

        guard let archiveURL = session.currentArchiveURL else {
            return provider
        }

        let ext = (filename as NSString).pathExtension.lowercased()
        let typeIdentifier: String
        if entry.type == .directory {
            if ext == "app" {
                typeIdentifier = UTType.application.identifier
            } else {
                typeIdentifier = UTType.folder.identifier
            }
        } else if let ut = UTType(filenameExtension: ext) {
            typeIdentifier = ut.identifier
        } else {
            typeIdentifier = UTType.data.identifier
        }

        let stagingSessionID = UUID().uuidString
        let stagingFolder = cacheDirectory.appendingPathComponent(stagingSessionID, isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)

        let broker = session.broker
        let isDirectory = entry.type == .directory
        let descendants = isDirectory ? ((try? session.entryIndex?.descendants(of: entry.path)) ?? [entry]) : [entry]

        // Thread-safe detached extraction task so it never blocks or deadlocks with the MainActor
        let extractTask = Task.detached(priority: .userInitiated) { () -> URL? in
            do {
                if isDirectory {
                    try await broker.extract(archiveURL, entries: descendants, to: stagingFolder)
                } else {
                    try await broker.extract(archiveURL, entries: [entry], to: stagingFolder)
                }

                // Locate the extracted item inside staging
                var targetURL = stagingFolder.appendingPathComponent(entry.path)
                if !FileManager.default.fileExists(atPath: targetURL.path) {
                    let stripped = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let alt = stagingFolder.appendingPathComponent(stripped)
                    if FileManager.default.fileExists(atPath: alt.path) {
                        targetURL = alt
                    } else if let enumerator = FileManager.default.enumerator(at: stagingFolder, includingPropertiesForKeys: nil) {
                        while let item = enumerator.nextObject() {
                            if let obj = item as? URL, obj.lastPathComponent == entry.name {
                                targetURL = obj
                                break
                            }
                        }
                    }
                }

                if FileManager.default.fileExists(atPath: targetURL.path) {
                    return targetURL
                }
            } catch {}
            return nil
        }

        // 1. Primary file representation (used by Finder/Desktop to accept dropped files)
        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completionHandler in
            Task.detached(priority: .userInitiated) {
                if let url = await extractTask.value {
                    completionHandler(url, false, nil)
                } else {
                    completionHandler(nil, false, ArchiveEngineError.io("未能提取拖拽文件: \(filename)"))
                }
            }
            return Progress(totalUnitCount: max(1, entry.uncompressedSize))
        }

        // 2. Fallback item / data representation
        if typeIdentifier != UTType.data.identifier {
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.data.identifier,
                fileOptions: [],
                visibility: .all
            ) { completionHandler in
                Task.detached(priority: .userInitiated) {
                    if let url = await extractTask.value {
                        completionHandler(url, false, nil)
                    } else {
                        completionHandler(nil, false, ArchiveEngineError.io("未能提取拖拽文件: \(filename)"))
                    }
                }
                return Progress(totalUnitCount: max(1, entry.uncompressedSize))
            }
        }

        return provider
    }
}
