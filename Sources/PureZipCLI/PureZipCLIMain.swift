import Foundation
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

@main
struct PureZipCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let subcommand = args.first else {
            printUsage()
            return
        }

        let broker = ArchiveEngineBroker()

        do {
            switch subcommand {
            case "probe":
                guard args.count >= 2 else {
                    printUsage()
                    Foundation.exit(1)
                }
                let url = URL(fileURLWithPath: args[1]).standardizedFileURL
                let desc = try await broker.descriptor(for: url)
                let isSplit = ArchiveVolumeFamily.isSplitArchive(at: url)
                let primary = ArchiveVolumeFamily.primaryURL(for: url)
                let members = ArchiveVolumeFamily.memberURLs(for: url)
                let fp = try ArchiveSourceFingerprint.capture(at: primary)

                print("Format:           \(desc.displayName) (\(desc.format.rawValue))")
                print("Support Tier:     \(desc.tier.rawValue)")
                print("Signed Container: \(desc.signedContainer)")
                print("Split Archive:    \(isSplit) (primary: \(primary.lastPathComponent), members: \(members.count))")
                print("Fingerprint:      dev=\(fp.deviceNumber) ino=\(fp.fileNumber) size=\(fp.byteCount) mtime_ns=\(fp.modificationNanoseconds)")

            case "list":
                guard args.count >= 2 else {
                    printUsage()
                    Foundation.exit(1)
                }
                let url = URL(fileURLWithPath: args[1]).standardizedFileURL
                let rootOnly = args.contains("--root-only")
                let includeAux = args.contains("--include-auxiliary")
                var parentDir = ""
                var searchQuery: String?

                var idx = 2
                while idx < args.count {
                    if args[idx] == "--parent", idx + 1 < args.count {
                        parentDir = args[idx + 1]
                        idx += 2
                    } else if args[idx] == "--search", idx + 1 < args.count {
                        searchQuery = args[idx + 1]
                        idx += 2
                    } else {
                        idx += 1
                    }
                }

                if rootOnly {
                    let roots = try await broker.initialRootEntries(url, limit: 200)
                    for entry in roots {
                        printEntry(entry)
                    }
                    return
                }

                let index = try EntryIndex()
                let stream = try await broker.list(url)
                for try await batch in stream {
                    try index.insert(batch)
                }

                let results: [ArchiveEntry]
                if let query = searchQuery {
                    results = try index.page(search: query, includeAuxiliary: includeAux)
                } else {
                    results = try index.children(of: parentDir, includeAuxiliary: includeAux)
                }

                let stats = try index.childStatistics(of: parentDir)
                print("Indexed \(try index.count()) entries (directory '\(parentDir)': \(stats.nonAuxiliaryCount) visible, \(stats.totalCount) total)")
                for entry in results {
                    printEntry(entry)
                }

            case "create":
                guard args.count >= 3 else {
                    printUsage()
                    Foundation.exit(1)
                }
                let outURL = URL(fileURLWithPath: args[1]).standardizedFileURL
                let sources = args.dropFirst(2).map { URL(fileURLWithPath: $0).standardizedFileURL }
                let desc = ArchiveFormatDescriptor.detect(at: outURL)
                let format = desc.format == .unknown ? .zip : desc.format
                let profile = CompressionProfile(format: format, level: 6)

                let registry = try ManagedTemporaryArtifactRegistry()
                let lease = try await registry.reserveArchivePublication(finalURL: outURL)
                do {
                    try await broker.create(
                        sources: sources,
                        at: lease.stagedPrimaryURL,
                        profile: profile
                    )
                    let result = try await lease.commit()
                    print("Created archive: \(result.primaryURL.path)")
                } catch {
                    await lease.rollbackAndWait()
                    throw error
                }

            case "extract":
                guard args.count >= 3 else {
                    printUsage()
                    Foundation.exit(1)
                }
                let archiveURL = URL(fileURLWithPath: args[1]).standardizedFileURL
                let destURL = URL(fileURLWithPath: args[2]).standardizedFileURL

                let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "cli-extract")
                defer { stageLease.release() }

                try await broker.quickExtractAll(archiveURL, to: stageLease.url)
                let manifest = try ExtractionFinalizationManifest.prepare(stagingDirectory: stageLease.url)
                var collisionIndex = DestinationCollisionIndex()
                let published = try FinderExtractionPublisher.publishMergingContents(
                    using: manifest,
                    to: destURL,
                    collisionIndex: &collisionIndex,
                    directoryConflictPolicy: .rename
                )
                print("Extracted \(manifest.totalNodeCount) items (filtered \(manifest.filteredItemCount) metadata items) -> \(published.map(\.lastPathComponent).joined(separator: ", "))")

            case "test":
                guard args.count >= 2 else {
                    printUsage()
                    Foundation.exit(1)
                }
                let archiveURL = URL(fileURLWithPath: args[1]).standardizedFileURL
                try await broker.test(archiveURL)
                print("OK: Archive integrity verified (\(archiveURL.lastPathComponent))")

            case "self-test":
                try await CLISelfTestRunner.runAll()

            default:
                printUsage()
                Foundation.exit(1)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func printEntry(_ entry: ArchiveEntry) {
        let kindTag: String
        switch entry.type {
        case .directory:    kindTag = "DIR "
        case .symbolicLink: kindTag = "LINK"
        case .hardLink:     kindTag = "HLNK"
        case .file:         kindTag = "FILE"
        case .other:        kindTag = "OTHR"
        }
        let crcStr = entry.checksum.map { String(format: "%08X", $0) } ?? "--------"
        print(String(format: "[%@] %10lld -> %10lld  CRC:%@  %@", kindTag, entry.uncompressedSize, entry.compressedSize, crcStr, entry.path))
    }

    private static func printUsage() {
        print("""
        PureZip CLI (Command-line utility for PureZip archive operations)
        Usage:
          purezip-cli probe <archive>
          purezip-cli list <archive> [--root-only] [--parent <dir>] [--search <query>] [--include-auxiliary]
          purezip-cli create <output-archive> <source1> [source2 ...]
          purezip-cli extract <archive> <destination-dir>
          purezip-cli test <archive>
        """)
    }
}
