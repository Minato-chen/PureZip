import Foundation
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

enum CLISelfTestRunner {
    static func assertTrue(_ condition: @autoclosure () -> Bool, _ msg: String = "Assertion failed", line: Int = #line) throws {
        if !condition() {
            throw NSError(domain: "PureZipSelfTest", code: line, userInfo: [NSLocalizedDescriptionKey: "Line \(line): \(msg)"])
        }
    }

    static func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ msg: String = "", line: Int = #line) throws {
        if lhs != rhs {
            throw NSError(domain: "PureZipSelfTest", code: line, userInfo: [NSLocalizedDescriptionKey: "Line \(line): Expected \(rhs), got \(lhs). \(msg)"])
        }
    }

    static func runAll() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PureZipSelfTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("[1/7] Testing ArchiveVolumeFamily & ArchiveOutputFamily...")
        try testVolumeAndOutputFamilies(tempDir: tempDir)

        print("[2/7] Testing SQLite EntryIndex (virtual directory synthesis, children, descendants range query)...")
        try testEntryIndexSQLiteHierarchyAndRangeQueries()

        print("[3/7] Testing LegacyCJKFilenameDecoder (GB18030 / CP932 Shift-JIS / UTF-8)...")
        try testLegacyCJKFilenameDecoding()

        print("[4/7] Testing SmartCompressionClassifier & ZIPEngine round-trip + ChangeSet + path traversal guard...")
        try await testSmartCompressionClassifierAndZIPEngineRoundTrip(tempDir: tempDir)

        print("[5/7] Testing SevenZipEngine.CatalogReader & BSDTarEngine (.tar.gz) round-trip...")
        try await testSevenZipCatalogReaderAndBSDTarEngine(tempDir: tempDir)

        print("[6/7] Testing ManagedTemporaryArtifactRegistry (commit/rollback) & ArchivePreviewSeedStore...")
        try await testManagedTemporaryArtifactRegistryAndPreviewSeedStore(tempDir: tempDir)

        print("[7/7] Testing PureZipFinderSupport, atomic .app protection in ExtractionFinalizationManifest & FinderExtractionPublisher...")
        try testFinderSupportAndExtractionFinalizationManifest(tempDir: tempDir)

        print("[8/8] Testing ArchiveCreationPurpose (Windows/Mac/Linux) & Windows Filename Compatibility Validator...")
        try testArchiveCreationPurposeAndWindowsCompatibility()

        print("[9/9] Testing PureZipPreferences persistence, system synchronizations & factory reset...")
        try await testPureZipPreferences()

        print("ALL 9 TEST SUITES PASSED SUCCESSFULLY!")
    }

    static func testVolumeAndOutputFamilies(tempDir: URL) throws {
        let fm = FileManager.default
        let part1 = tempDir.appendingPathComponent("backup.7z.001")
        let part2 = tempDir.appendingPathComponent("backup.7z.002")
        let part3 = tempDir.appendingPathComponent("backup.7z.003")
        try Data("p1".utf8).write(to: part1)
        try Data("p2".utf8).write(to: part2)
        try Data("p3".utf8).write(to: part3)

        try assertTrue(ArchiveVolumeFamily.isSplitArchive(at: part2, fileManager: fm))
        try assertEqual(ArchiveVolumeFamily.primaryURL(for: part3, fileManager: fm), part1)
        try assertEqual(ArchiveVolumeFamily.ownershipURL(for: part2), tempDir.appendingPathComponent("backup.7z"))
        try assertEqual(ArchiveVolumeFamily.memberURLs(for: part2, fileManager: fm), [part1, part2, part3])

        let z01 = tempDir.appendingPathComponent("photos.z01")
        let zipMain = tempDir.appendingPathComponent("photos.zip")
        try Data("z01".utf8).write(to: z01)
        try Data("zip".utf8).write(to: zipMain)
        try assertTrue(ArchiveVolumeFamily.isSplitArchive(at: zipMain, fileManager: fm))
        try assertEqual(ArchiveVolumeFamily.primaryURL(for: z01, fileManager: fm), zipMain)
        try assertEqual(ArchiveVolumeFamily.memberURLs(for: z01, fileManager: fm), [z01, zipMain])

        let tarGz = tempDir.appendingPathComponent("bundle.tar.gz")
        try Data("tgz".utf8).write(to: tarGz)
        let nextFree = ArchiveOutputFamily.collisionFreeBaseURL(for: tarGz, fileManager: fm)
        try assertEqual(nextFree.lastPathComponent, "bundle 2.tar.gz")
    }

    static func testEntryIndexSQLiteHierarchyAndRangeQueries() throws {
        let index = try EntryIndex()
        defer { index.close() }

        let entries: [ArchiveEntry] = [
            ArchiveEntry(path: "README.md", type: .file, uncompressedSize: 120, compressedSize: 80),
            ArchiveEntry(path: "src/core/engine.swift", type: .file, uncompressedSize: 4096, compressedSize: 1024),
            ArchiveEntry(path: "src/core/index.swift", type: .file, uncompressedSize: 2048, compressedSize: 600),
            ArchiveEntry(path: "src/ui/window.swift", type: .file, uncompressedSize: 1500, compressedSize: 500),
            ArchiveEntry(path: "__MACOSX/._README.md", type: .file, uncompressedSize: 64, compressedSize: 64),
            ArchiveEntry(path: ".DS_Store", type: .file, uncompressedSize: 4096, compressedSize: 512),
            ArchiveEntry(path: ".background/bg.png", type: .file, uncompressedSize: 8192, compressedSize: 8000),
            ArchiveEntry(path: "Applications", type: .symbolicLink, linkTarget: "/Applications")
        ]
        try index.insert(entries)
        try assertEqual(try index.count(), 8)

        let rootChildren = try index.children(of: "", includeAuxiliary: false)
        try assertEqual(rootChildren.map(\.path), ["src", "README.md"])
        try assertEqual(rootChildren.first?.type, .directory)

        let rootStats = try index.childStatistics(of: "")
        try assertEqual(rootStats.nonAuxiliaryCount, 2)
        try assertEqual(rootStats.totalCount, 6)

        let srcChildren = try index.children(of: "src")
        try assertEqual(srcChildren.map(\.path), ["src/core", "src/ui"])

        let coreChildren = try index.children(of: "src/core")
        try assertEqual(coreChildren.map(\.path), ["src/core/engine.swift", "src/core/index.swift"])

        let descendants = try index.descendants(of: "src/core")
        try assertEqual(descendants.map(\.path), ["src/core/engine.swift", "src/core/index.swift"])

        let searchHits = try index.page(search: "swift")
        try assertEqual(searchHits.count, 3)

        let existingDirs = try index.existingDirectoryAncestors(for: ["src", "src/core", "nonexistent"])
        try assertEqual(existingDirs, ["src", "src/core"])

        // Test in-archive rename (staged editing & undo support)
        let newDoc = ArchiveEntry(path: "src/core/engine_v2.swift", type: .file)
        try index.rename(oldCanonicalPath: "src/core/engine.swift", to: newDoc)
        let updatedCore = try index.children(of: "src/core")
        try assertEqual(updatedCore.map(\.path), ["src/core/engine_v2.swift", "src/core/index.swift"])

        // Test in-archive remove
        try index.remove(canonicalPaths: ["src/core/index.swift"])
        let afterDelete = try index.children(of: "src/core")
        try assertEqual(afterDelete.map(\.path), ["src/core/engine_v2.swift"])
    }

    static func testLegacyCJKFilenameDecoding() throws {
        let chineseString = "测试文档/说明.txt"
        let gbEnc = LegacyFilenameEncoding.gb18030.stringEncoding
        guard let gbBytes = chineseString.data(using: gbEnc) else {
            throw ArchiveEngineError.io("GB18030 encoding failed")
        }
        let decodedCN = LegacyCJKFilenameDecoder.decodePath(gbBytes, utf8FlagSet: false)
        try assertEqual(decodedCN.path, chineseString)
        try assertTrue(decodedCN.encoding == .gb18030 || decodedCN.encoding == .gbk)

        let japaneseString = "アーカイブ/仕様書.txt"
        let sjisEnc = LegacyFilenameEncoding.cp932.stringEncoding
        guard let sjisBytes = japaneseString.data(using: sjisEnc) else {
            throw ArchiveEngineError.io("CP932 encoding failed")
        }
        let decodedJP = LegacyCJKFilenameDecoder.decodePath(sjisBytes, utf8FlagSet: false)
        try assertEqual(decodedJP.path, japaneseString)
        try assertEqual(decodedJP.encoding, .cp932)
    }

    static func testSmartCompressionClassifierAndZIPEngineRoundTrip(tempDir: URL) async throws {
        let srcFolder = tempDir.appendingPathComponent("ProjectSource", isDirectory: true)
        try FileManager.default.createDirectory(at: srcFolder, withIntermediateDirectories: true)

        let textFile = srcFolder.appendingPathComponent("repeated.txt")
        let compressibleContent = String(repeating: "PureZip architecture verification line.\n", count: 200)
        try Data(compressibleContent.utf8).write(to: textFile)

        let tinyFile = srcFolder.appendingPathComponent("tiny.txt")
        try Data("hi".utf8).write(to: tinyFile)

        let textDecision = SmartCompressionClassifier.classify(fileAt: textFile, compressionLevel: 6)
        try assertEqual(textDecision.intent, .compress)

        let tinyDecision = SmartCompressionClassifier.classify(fileAt: tinyFile, compressionLevel: 6)
        try assertEqual(tinyDecision.intent, .store)
        try assertEqual(tinyDecision.evidence, .smallNeutralFile)

        let broker = ArchiveEngineBroker()
        let zipURL = tempDir.appendingPathComponent("output.zip")
        try await broker.create(
            sources: [srcFolder],
            at: zipURL,
            profile: CompressionProfile(format: .zip, level: 6)
        )

        let desc = try await broker.descriptor(for: zipURL)
        try assertEqual(desc.format, .zip)

        let roots = try await broker.initialRootEntries(zipURL, limit: 50)
        try assertEqual(roots.map(\.path), ["ProjectSource"])

        try await broker.test(zipURL)

        let extraFile = tempDir.appendingPathComponent("added.md")
        try Data("# Added via ChangeSet\n".utf8).write(to: extraFile)
        let changes = ChangeSet(operations: [
            .add(sourceURL: extraFile, archivePath: "ProjectSource/added.md")
        ])
        try await broker.apply(changes, to: zipURL, profile: CompressionProfile(format: .zip, level: 6))

        let extractDir = tempDir.appendingPathComponent("ExtractedZIP", isDirectory: true)
        try await broker.quickExtractAll(zipURL, to: extractDir)

        let extractedText = try String(contentsOf: extractDir.appendingPathComponent("ProjectSource/repeated.txt"))
        try assertEqual(extractedText, compressibleContent)
        let extractedAdded = try String(contentsOf: extractDir.appendingPathComponent("ProjectSource/added.md"))
        try assertEqual(extractedAdded, "# Added via ChangeSet\n")

        var rejectedUnsafe = false
        do {
            _ = try ZIPEngine.validatedDestinationURL(for: "../escape.txt", inside: extractDir)
        } catch {
            rejectedUnsafe = true
        }
        try assertTrue(rejectedUnsafe, "Expected path traversal to be rejected")
    }

    static func testSevenZipCatalogReaderAndBSDTarEngine(tempDir: URL) async throws {
        let sampleSLT = """
        7-Zip 26.04 (arm64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-01-01
        Listing archive: sample.7z

        --
        Path = sample.7z
        Type = 7z
        Comment =
        {
        Multi-line archive header comment
        Line 2
        }
        Solid = +

        ----------
        Path = docs
        Folder = +
        Size = 0
        Packed Size = 0
        Modified = 2026-10-24 00:15:00
        Attributes = D_ drwxr-xr-x

        Path = docs/guide.md
        Folder = -
        Size = 2048
        Packed Size = 712
        Modified = 2026-10-24 00:15:30
        Attributes = _ -rw-r--r--
        CRC = 1A2B3C4D
        Encrypted = -

        """
        let catalog = SevenZipEngine.CatalogReader.parse(sltOutput: sampleSLT, archiveRootName: "sample.7z")
        try assertEqual(catalog.archiveComment, "Multi-line archive header comment\nLine 2")
        try assertEqual(catalog.entries.count, 2)
        try assertEqual(catalog.entries[0].path, "docs")
        try assertEqual(catalog.entries[0].type, .directory)
        try assertEqual(catalog.entries[1].path, "docs/guide.md")
        try assertEqual(catalog.entries[1].checksum, 0x1A2B3C4D)

        // Multi-container APFS DMG header test (`--` Dmg -> `----` 4.disk image -> `--` APFS -> `----------`)
        let sampleDMGSLT = """
        7-Zip (z) 26.05 (arm64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-10-21
        Listing archive: MacPlay-1.2.4-arm64.dmg

        --
        Path = /Users/minato/Desktop/ziptest/MacPlay-1.2.4-arm64.dmg
        Type = Dmg
        Comment = 
        {
        unpack-size: 260580352
        }
        ----
        Path = 4.disk image（Apple_APFS：4）
        Size = 260542464
        Comment = disk image（Apple_APFS：4）
        --
        Path = 4.disk image（Apple_APFS：4）
        Type = APFS
        Name = MacPlay.apfs
        Comment = 
        {
        volume_name: MacPlay
        }

        ----------
        Path = MacPlay.app
        Size = 
        Packed Size = 
        Mode = drwxr-xr-x
        Modified = 2026-09-30 03:47:23.763701953

        Path = Applications
        Size = 14
        Packed Size = 14
        Mode = lrwxr-xr-x
        Symbolic Link = /Applications

        """
        let dmgCatalog = SevenZipEngine.CatalogReader.parse(sltOutput: sampleDMGSLT, archiveRootName: "MacPlay-1.2.4-arm64.dmg")
        try assertEqual(dmgCatalog.entries.count, 2)
        try assertEqual(dmgCatalog.entries[0].path, "MacPlay.app")
        try assertEqual(dmgCatalog.entries[0].type, .directory)
        try assertEqual(dmgCatalog.entries[1].path, "Applications")
        try assertEqual(dmgCatalog.entries[1].type, .symbolicLink)
        try assertTrue(dmgCatalog.entries[1].isDMGApplicationsShortcut)

        let srcFile = tempDir.appendingPathComponent("hello.txt")
        try Data("Hello from BSDTarEngine!\n".utf8).write(to: srcFile)
        let tarGzURL = tempDir.appendingPathComponent("archive.tar.gz")
        let tarEngine = BSDTarEngine()

        try await tarEngine.create(
            sources: [srcFile],
            at: tarGzURL,
            profile: CompressionProfile(format: .tar)
        )
        try await tarEngine.test(tarGzURL)

        var listed: [ArchiveEntry] = []
        for try await batch in tarEngine.list(tarGzURL, password: nil) {
            listed.append(contentsOf: batch)
        }
        try assertEqual(listed.map(\.path), ["hello.txt"])

        let tarOutDir = tempDir.appendingPathComponent("TarOut", isDirectory: true)
        try await tarEngine.extract(tarGzURL, entries: [], to: tarOutDir)
        let restored = try String(contentsOf: tarOutDir.appendingPathComponent("hello.txt"))
        try assertEqual(restored, "Hello from BSDTarEngine!\n")
    }

    static func testManagedTemporaryArtifactRegistryAndPreviewSeedStore(tempDir: URL) async throws {
        let registry = try ManagedTemporaryArtifactRegistry()
        let finalArchiveURL = tempDir.appendingPathComponent("transactional.zip")

        let rollbackLease = try await registry.reserveArchivePublication(finalURL: finalArchiveURL)
        try Data("partial data".utf8).write(to: rollbackLease.stagedPrimaryURL)
        try assertTrue(FileManager.default.fileExists(atPath: rollbackLease.stagedPrimaryURL.path))
        await rollbackLease.rollbackAndWait()
        try assertTrue(!FileManager.default.fileExists(atPath: rollbackLease.stagedPrimaryURL.path))
        try assertTrue(!FileManager.default.fileExists(atPath: finalArchiveURL.path))

        let commitLease = try await registry.reserveArchivePublication(finalURL: finalArchiveURL)
        try Data("committed archive payload".utf8).write(to: commitLease.stagedPrimaryURL)
        let result = try await commitLease.commit()
        try assertEqual(result.primaryURL, finalArchiveURL)
        try assertTrue(FileManager.default.fileExists(atPath: finalArchiveURL.path))

        let seedStore = ArchivePreviewSeedStore(rootDirectory: tempDir.appendingPathComponent("Seeds", isDirectory: true))
        let fp = try ArchiveSourceFingerprint.capture(at: finalArchiveURL)
        let sampleEntries = [ArchiveEntry(path: "inside.txt", type: .file, uncompressedSize: 42, compressedSize: 21)]
        let handle = try await seedStore.publish(
            fingerprint: fp,
            format: .zip,
            entries: sampleEntries,
            isAuthoritativeForAppListing: true
        )
        try await seedStore.storeThumbnail(Data([0x89, 0x50, 0x4E, 0x47]), for: "inside.txt", in: handle)

        let claimed = try await seedStore.claim(matching: fp)
        try assertEqual(claimed?.entries, sampleEntries)
        try assertEqual(claimed?.thumbnails["inside.txt"], Data([0x89, 0x50, 0x4E, 0x47]))
    }

    static func testFinderSupportAndExtractionFinalizationManifest(tempDir: URL) throws {
        let fm = FileManager.default
        let stagingDir = tempDir.appendingPathComponent("Staging", isDirectory: true)

        let macosxDir = stagingDir.appendingPathComponent("__MACOSX", isDirectory: true)
        try fm.createDirectory(at: macosxDir, withIntermediateDirectories: true)
        try Data("appledouble".utf8).write(to: macosxDir.appendingPathComponent("._Sample.app"))
        try Data("dsstore".utf8).write(to: stagingDir.appendingPathComponent(".DS_Store"))

        let appResources = stagingDir.appendingPathComponent("Sample.app/Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: appResources, withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: stagingDir.appendingPathComponent("Sample.app/Contents/Info.plist"))
        try Data("keep-inside-app".utf8).write(to: appResources.appendingPathComponent("._icon.icns"))

        let manifest = try ExtractionFinalizationManifest.prepare(stagingDirectory: stagingDir)
        try assertEqual(manifest.topLevelNodes.map(\.name), ["Sample.app"])
        try assertTrue(manifest.filteredItemCount >= 2)
        try assertTrue(fm.fileExists(atPath: appResources.appendingPathComponent("._icon.icns").path))

        let destDir = tempDir.appendingPathComponent("ApplicationsOut", isDirectory: true)
        var collisionIndex = DestinationCollisionIndex()
        let firstPublished = try FinderExtractionPublisher.publishMergingContents(
            using: manifest,
            to: destDir,
            collisionIndex: &collisionIndex,
            directoryConflictPolicy: .rename
        )
        try assertEqual(firstPublished.map(\.lastPathComponent), ["Sample.app"])

        let store = FinderActionRequestStore(rootDirectory: tempDir.appendingPathComponent("Requests", isDirectory: true))
        let req = try FinderActionRequest(action: .quickExtractHere, sources: [firstPublished[0]])
        try assertTrue(req.action.isExtraction)
        try assertTrue(req.action.launchesInBackground)

        let reqFile = try store.write(req)
        let launchURL = FinderActionLaunchURL.make(requestID: req.id, requestFileURL: reqFile)
        try assertEqual(launchURL.scheme, "purezip")
        guard let ref = FinderActionLaunchURL.reference(from: launchURL) else {
            throw FinderActionError.invalidLaunchURL
        }
        let consumed = try store.consume(ref)
        try assertEqual(consumed, req)
    }

    static func testArchiveCreationPurposeAndWindowsCompatibility() throws {
        // Purpose defaults
        try assertTrue(ArchiveCreationPurpose.windows.filtersMacAuxiliary)
        try assertTrue(!ArchiveCreationPurpose.windows.preservesMacMetadata)
        try assertTrue(ArchiveCreationPurpose.mac.preservesMacMetadata)

        // Windows filename compatibility validation
        let samplePaths = [
            "normal_file.txt",
            "docs/report:draft.pdf",         // ':' is illegal in Windows
            "photos/vacation?.jpg",          // '?' is illegal in Windows
            "data/CON.txt",                  // 'CON' is reserved in DOS/Windows
            "data/aux.png",                  // 'AUX' is reserved in DOS/Windows
            "notes/trailing_dot.",           // trailing dot is invalid in Windows
            "notes/trailing_space ",         // trailing space is invalid in Windows
            "交接资料/上线协作计划.pdf.",        // CJK filename with trailing dot
            "tools/valid_name_windows.zip"
        ]

        let issues = ArchiveCreationPurpose.validateWindowsCompatibility(paths: samplePaths)
        try assertEqual(issues.count, 7)

        let conIssue = issues.first { $0.originalPath == "data/CON.txt" }
        try assertTrue(conIssue != nil)
        try assertEqual(conIssue?.suggestedFilename, "CON-file.txt")
        try assertEqual(conIssue?.reasonDescription, "使用了 Windows 保留的设备名称")

        let dotIssue = issues.first { $0.originalPath == "交接资料/上线协作计划.pdf." }
        try assertTrue(dotIssue != nil)
        try assertEqual(dotIssue?.suggestedFilename, "上线协作计划.pdf")
        try assertEqual(dotIssue?.reasonDescription, "名称末尾的点在 Windows 中可能消失")

        let reasons = issues.map(\.reason)
        try assertTrue(reasons.contains(.illegalCharacter))
        try assertTrue(reasons.contains(.reservedDeviceName))
        try assertTrue(reasons.contains(.trailingDotOrSpace))

        // Check split volume presets
        try assertEqual(ArchiveCreationVolumeSize.mb10.byteCount, 10 * 1024 * 1024)
        try assertEqual(ArchiveCreationVolumeSize.cd700.byteCount, 700 * 1024 * 1024)
    }

    @MainActor
    static func testPureZipPreferences() async throws {
        let suiteName = "com.minato.purezip.TestPreferences"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        let prefs = PureZipPreferences(defaults: testDefaults)

        // 1. General & Appearance
        try assertEqual(prefs.appearanceMode, "auto")
        prefs.appearanceMode = "dark"
        try assertEqual(testDefaults.string(forKey: "PureZip.General.AppearanceMode"), "dark")

        // 2. Compression defaults
        try assertEqual(prefs.compressionPurpose, .general)
        prefs.compressionPurpose = .windows
        try assertEqual(testDefaults.string(forKey: "PureZip.Compression.DefaultPurpose"), "windows")

        // 3. Extraction post-action & quick extract
        try assertTrue(!prefs.quickExtractOnDoubleClick)
        prefs.quickExtractOnDoubleClick = true
        try assertTrue(testDefaults.bool(forKey: "PureZip.Extraction.QuickExtractOnDoubleClick"))

        try assertEqual(prefs.extractionPostAction, "每次均询问")
        prefs.extractionPostAction = "移入废纸篓"
        try assertEqual(testDefaults.string(forKey: "PureZip.Extraction.PostAction"), "移入废纸篓")

        // 4. Pure Actions quick install & format set
        try assertTrue(prefs.pureActionsQuickInstall)
        prefs.pureActionsQuickInstall = false
        try assertTrue(!testDefaults.bool(forKey: "PureZip.PureActions.QuickInstall"))

        // 5. Pure Capsule & Pure Shelf
        prefs.pureShelfColorIndex = 3
        prefs.pureShelfColorIntensity = 75.0
        try assertEqual(testDefaults.integer(forKey: "PureZip.PureShelf.ColorIndex"), 3)
        try assertEqual(testDefaults.double(forKey: "PureZip.PureShelf.ColorIntensity"), 75.0)

        // 6. Reset
        prefs.resetAllSettings()
        try assertEqual(prefs.compressionPurpose, .general)
        try assertEqual(prefs.pureShelfColorIndex, 0)
        try assertEqual(prefs.pureShelfColorIntensity, 35.0)

        testDefaults.removePersistentDomain(forName: suiteName)
    }
}
