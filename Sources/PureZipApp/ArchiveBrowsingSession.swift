import AppKit
import SwiftUI
import PDFKit
import QuickLookThumbnailing
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

@MainActor
public final class ArchiveBrowsingSession: ObservableObject {

    public enum WindowPresentationMode: String, CaseIterable, Identifiable {
        case completeDesk = "完整工作区"
        case capsuleFloating      = "Pure Capsule 悬浮窗"
        public var id: String { rawValue }
    }

    public enum DMGViewMode: String, CaseIterable, Identifiable {
        case canvas = "画布"
        case list   = "列表"
        public var id: String { rawValue }
    }

    public struct NestedArchiveCrumb: Identifiable {
        public let id = UUID()
        public let archiveURL: URL
        public let displayName: String
        public let directoryPath: String
        public let workLease: ManagedWorkFileLease?
    }

    public struct NestedArchivePreviewSummary: Sendable {
        public let formatDisplayName: String
        public let totalEntryCount: Int
        public let totalUncompressedBytes: Int64
        public let topEntries: [ArchiveEntry]

        public init(
            formatDisplayName: String,
            totalEntryCount: Int,
            totalUncompressedBytes: Int64,
            topEntries: [ArchiveEntry]
        ) {
            self.formatDisplayName = formatDisplayName
            self.totalEntryCount = totalEntryCount
            self.totalUncompressedBytes = totalUncompressedBytes
            self.topEntries = topEntries
        }
    }

    public struct SelectedEntryPreview {
        public let entry: ArchiveEntry
        public let textContent: String?
        public let hexPreview: String
        public let image: NSImage?
        public let classifierDecision: SmartCompressionClassifier.FileDecision?
        public let model3DURL: URL?
        public let mediaFileURL: URL?
        public let audioMetadata: AudioPreviewData?
        public let videoMetadata: VideoPreviewData?
        public let nestedArchiveSummary: NestedArchivePreviewSummary?

        public init(
            entry: ArchiveEntry,
            textContent: String?,
            hexPreview: String,
            image: NSImage?,
            classifierDecision: SmartCompressionClassifier.FileDecision?,
            model3DURL: URL? = nil,
            mediaFileURL: URL? = nil,
            audioMetadata: AudioPreviewData? = nil,
            videoMetadata: VideoPreviewData? = nil,
            nestedArchiveSummary: NestedArchivePreviewSummary? = nil
        ) {
            self.entry = entry
            self.textContent = textContent
            self.hexPreview = hexPreview
            self.image = image
            self.classifierDecision = classifierDecision
            self.model3DURL = model3DURL
            self.mediaFileURL = mediaFileURL
            self.audioMetadata = audioMetadata
            self.videoMetadata = videoMetadata
            self.nestedArchiveSummary = nestedArchiveSummary
        }
    }

    public enum StagedArchiveOperation: Sendable, Hashable {
        case delete(entry: ArchiveEntry)
        case rename(originalEntry: ArchiveEntry, newEntry: ArchiveEntry)
        case add(sourceURL: URL, archivePath: String, primaryEntry: ArchiveEntry, allCreatedEntries: [ArchiveEntry])
    }

    // MARK: - Published UI State

    @Published public var windowMode: WindowPresentationMode = PureZipPreferences.shared.openWithCapsuleByDefault ? .capsuleFloating : .completeDesk
    @Published public var viewMode: DeskViewMode = {
        switch PureZipPreferences.shared.defaultViewMode.lowercased() {
        case "icons", "图标": return .icons
        case "columns", "分栏": return .columns
        default: return .list
        }
    }()
    @Published public var dmgViewMode: DMGViewMode = .canvas
    @Published public var diskImagePresentation: DiskImagePresentation? = nil
    @Published public var dmgAppIcon: NSImage? = nil
    @Published public var isDMGCapsuleExpanded: Bool = false
    @Published public var isPinnedOnTop: Bool = false {
        didSet { updateWindowFloatingLevel() }
    }

    @Published public var currentArchiveURL: URL?
    @Published public var currentDescriptor: ArchiveFormatDescriptor?
    @Published public var isSplitVolume: Bool = false
    @Published public var splitMemberCount: Int = 1
    @Published public var archiveComment: String?

    @Published public var currentDirectoryPath: String = ""
    @Published public var searchQuery: String = "" {
        didSet {
            try? refreshDisplayedEntries()
        }
    }
    @Published public var includeAuxiliary: Bool = PureZipPreferences.shared.includeAuxiliary

    @Published public var displayedEntries: [ArchiveEntry] = []
    @Published public var selectedEntryID: String?
    @Published public var selectedEntryPreview: SelectedEntryPreview?
    @Published public var isLoadingEntryPreview: Bool = false
    @Published public var containsNestedArchives: Bool = false
    @Published public var gridColumnCount: Int = 6
    public let columnBrowserState = ColumnBrowserState()
    @Published public var hoveredCandidate: HoverPreviewCandidate?
    @Published public var quickLookItemURL: URL? = nil

    // Window session-scoped media playback states (resets on window/archive close)
    @Published public var sessionVideoAutoPlay: Bool = PureZipPreferences.shared.deskVideoAutoPlay
    @Published public var sessionVideoLoop: Bool = false
    @Published public var sessionAudioAutoPlay: Bool = PureZipPreferences.shared.deskAudioAutoPlay
    @Published public var sessionAudioLoop: Bool = PureZipPreferences.shared.deskAudioLoop
    @Published public var sessionMediaMuted: Bool = PureZipPreferences.shared.deskMediaAlwaysMute
    private var prefetchTask: Task<Void, Never>?

    // Creation Sheet Trigger
    @Published public var creationSources: [URL]? = nil
    @Published public var isShowingSettings: Bool = false
    @Published public var selectedSettingsTab: SettingsView.SettingsTab = .pureShelf

    // Password Prompt
    @Published public var currentArchivePassword: String? = nil
    @Published public var isShowingPasswordPrompt: Bool = false
    @Published public var passwordPromptErrorMessage: String? = nil
    @Published public var passwordPromptAction: (@MainActor (String) -> Void)? = nil

    // Staged Editing, Undo/Redo & Save State
    @Published public var undoStack: [StagedArchiveOperation] = []
    @Published public var redoStack: [StagedArchiveOperation] = []
    @Published public var hasUnsavedChanges: Bool = false
    @Published public var indexRevision: Int = 0

    // In-Archive Rename State
    @Published public var entryBeingRenamed: ArchiveEntry? = nil
    @Published public var isShowingRenameSheet: Bool = false

    public func promptForPassword(errorMessage: String? = nil, onComplete: @escaping @MainActor (String) -> Void) {
        self.passwordPromptErrorMessage = errorMessage
        self.passwordPromptAction = onComplete
        self.isShowingPasswordPrompt = true
    }

    public func submitPassword(_ pwd: String) {
        self.isShowingPasswordPrompt = false
        self.passwordPromptErrorMessage = nil
        let action = self.passwordPromptAction
        self.passwordPromptAction = nil
        action?(pwd)
    }

    public func cancelPasswordPrompt() {
        self.isShowingPasswordPrompt = false
        self.passwordPromptErrorMessage = nil
        self.passwordPromptAction = nil
    }

    public weak var mainWindow: NSWindow?

    public func openMainWindow() {
        self.currentArchiveURL = nil
        if let win = mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            MainWindowController.shared.show(session: self)
        }
    }

    public func openSettings(tab: SettingsView.SettingsTab = .pureShelf) {
        self.selectedSettingsTab = tab
        SettingsWindowController.shared.show(session: self)
    }

    public func closeSettings() {
        self.isShowingSettings = false
        SettingsWindowController.shared.close()
    }

    @Published public var totalIndexedCount: Int = 0
    @Published public var currentChildStats = EntryIndex.MatchStatistics(totalCount: 0, nonAuxiliaryCount: 0)

    @Published public var nestedStack: [NestedArchiveCrumb] = []
    @Published public var recentArchives: [URL] = []

    // Pure Shelf (Menu Bar Drop Shelf)
    @Published public var shelfItems: [URL] = []
    @Published public var shelfFormat: ArchiveFormat = .zip

    // Status & Progress
    @Published public var isBusy: Bool = false
    @Published public var statusMessage: String = "就绪 — 打开或拖入归档文件以开始浏览"
    @Published public var lastLoadError: String? = nil
    @Published public var progressFraction: Double?

    // MARK: - Core Subsystems

    public let broker = ArchiveEngineBroker()
    public let xpcTransport = XPCWorkerClientTransport()
    public let previewSeedStore = ArchivePreviewSeedStore()
    public private(set) var entryIndex: EntryIndex?
    private var activeNestedLeases: [ManagedWorkFileLease] = []
    private var previewLoadTask: Task<Void, Never>?
    private var currentOpenTaskID: UUID = UUID()
    private var activeMediaTempURL: URL?

    public var isCapsuleMode: Bool {
        return windowMode == .capsuleFloating || currentDescriptor?.format == .dmg
    }

    public init() {}

    deinit {
        previewLoadTask?.cancel()
        if let temp = activeMediaTempURL {
            try? FileManager.default.removeItem(at: temp)
        }
        for lease in activeNestedLeases { lease.release() }
    }

    // MARK: - Window Pinning & Mode Switching

    public func toggleWindowMode() {
        if currentDescriptor?.format == .dmg {
            isDMGCapsuleExpanded.toggle()
            windowMode = .capsuleFloating
            if let window = mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) }) {
                let targetSize = isDMGCapsuleExpanded
                    ? NSSize(width: 680, height: 500)
                    : NSSize(width: 420, height: 440)
                var frame = window.frame
                let dy = frame.size.height - targetSize.height
                let dx = frame.size.width - targetSize.width
                frame.origin.y += dy
                frame.origin.x += (dx / 2.0)
                frame.size = targetSize
                window.minSize = isDMGCapsuleExpanded ? NSSize(width: 440, height: 380) : NSSize(width: 360, height: 340)
                window.setFrame(frame, display: true, animate: true)
            }
            updateWindowFloatingLevel()
            return
        }

        windowMode = (windowMode == .completeDesk) ? .capsuleFloating : .completeDesk
        if let window = mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) }) {
            let targetSize = (windowMode == .capsuleFloating)
                ? NSSize(width: 420, height: 440)
                : NSSize(width: 1080, height: 680)
            var frame = window.frame
            let dy = frame.size.height - targetSize.height
            frame.origin.y += dy
            frame.size = targetSize
            window.minSize = (windowMode == .capsuleFloating) ? NSSize(width: 360, height: 340) : NSSize(width: 860, height: 560)
            window.setFrame(frame, display: true, animate: true)
        }
        updateWindowFloatingLevel()
    }

    public func updateWindowFloatingLevel() {
        var targets = NSApp.windows.filter { !($0 is NSPanel) }
        if let main = mainWindow, !targets.contains(main) {
            targets.append(main)
        }
        for window in targets {
            if isPinnedOnTop {
                window.level = .floating
                window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle])
                window.hidesOnDeactivate = false
            } else {
                window.level = .normal
                window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle])
            }
        }
    }

    // MARK: - Two-Phase Archive Opening & SQLite Indexing

    public func openArchive(at rawURL: URL, resetNestedStack: Bool = true) async {
        let taskID = UUID()
        self.currentOpenTaskID = taskID
        previewLoadTask?.cancel()
        previewLoadTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        cleanupActiveMediaTemp()
        self.sessionVideoAutoPlay = PureZipPreferences.shared.deskVideoAutoPlay
        self.sessionVideoLoop = false
        self.sessionAudioAutoPlay = PureZipPreferences.shared.deskAudioAutoPlay
        self.sessionAudioLoop = PureZipPreferences.shared.deskAudioLoop
        self.sessionMediaMuted = PureZipPreferences.shared.deskMediaAlwaysMute

        let primaryURL = ArchiveVolumeFamily.primaryURL(for: rawURL)
        self.lastLoadError = nil
        self.statusMessage = "正在载入 \(primaryURL.lastPathComponent)..."
        self.isBusy = true

        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            if self.currentOpenTaskID == taskID {
                self.isBusy = false
                self.statusMessage = "找不到文件: \(primaryURL.path)"
                self.lastLoadError = "未能找到归档文件。若位于外接移动设备，请确认硬盘已正常挂载并连接稳定。"
            }
            return
        }

        if primaryURL != currentArchiveURL {
            currentArchivePassword = nil
        }

        if resetNestedStack {
            for lease in activeNestedLeases { lease.release() }
            activeNestedLeases.removeAll()
            nestedStack.removeAll()
            undoStack.removeAll()
            redoStack.removeAll()
            hasUnsavedChanges = false
        }

        progressFraction = nil
        selectedEntryID = nil
        selectedEntryPreview = nil
        displayedEntries = []
        currentDirectoryPath = ""
        searchQuery = ""
        archiveComment = nil
        entryIndex?.close()
        entryIndex = nil
        indexRevision += 1

        do {
            let desc = try await broker.descriptor(for: primaryURL)
            guard self.currentOpenTaskID == taskID && !Task.isCancelled else { return }

            if desc.format == .dmg {
                self.windowMode = .capsuleFloating
                self.isDMGCapsuleExpanded = false
            } else if resetNestedStack && self.currentArchiveURL == nil {
                self.windowMode = PureZipPreferences.shared.openWithCapsuleByDefault ? .capsuleFloating : .completeDesk
                self.includeAuxiliary = PureZipPreferences.shared.includeAuxiliary
            } else if resetNestedStack {
                self.includeAuxiliary = PureZipPreferences.shared.includeAuxiliary
            }
            self.currentArchiveURL = primaryURL
            self.currentDescriptor = desc
            self.isSplitVolume = ArchiveVolumeFamily.isSplitArchive(at: rawURL)
            self.splitMemberCount = ArchiveVolumeFamily.memberURLs(for: rawURL).count
            addRecentArchive(primaryURL)

            // Bring existing window to front or show once
            if let win = mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                MainWindowController.shared.show(session: self)
            }

            // Phase 1: Check PreviewSeedStore or fetch initialRootEntries for instant first paint
            if let fp = try? ArchiveSourceFingerprint.capture(at: primaryURL),
               let seedClaim = try? await previewSeedStore.claim(matching: fp) {
                guard self.currentOpenTaskID == taskID && !Task.isCancelled else { return }
                self.displayedEntries = ArchiveBrowserProjection.directChildren(
                    of: seedClaim.entries,
                    in: "",
                    includeAuxiliary: includeAuxiliary
                )
                statusMessage = "已从 QuickLook 预览种子极速加载 (\(seedClaim.entries.count) 项)"
            } else if desc.format != .dmg,
                      let initialRoots = try? await broker.initialRootEntries(primaryURL, format: desc.format, limit: 200) {
                guard self.currentOpenTaskID == taskID && !Task.isCancelled else { return }
                self.displayedEntries = initialRoots
                statusMessage = "正在构建 SQLite EntryIndex 目录树索引..."
            } else {
                guard self.currentOpenTaskID == taskID && !Task.isCancelled else { return }
                statusMessage = desc.format == .dmg ? "正在解析磁盘映像目录结构..." : "正在构建 SQLite EntryIndex 目录树索引..."
            }

            // Phase 2: Full streaming catalog into SQLite EntryIndex
            let newIndex = try EntryIndex()
            let stream = try await broker.list(primaryURL, password: currentArchivePassword) { [weak self] comment in
                Task { @MainActor in
                    self?.archiveComment = comment
                }
            }
            for try await batch in stream {
                guard self.currentOpenTaskID == taskID && !Task.isCancelled else { return }
                try newIndex.insert(batch)
            }
            guard self.currentOpenTaskID == taskID && !Task.isCancelled else { return }
            self.entryIndex = newIndex
            self.indexRevision += 1
            try refreshDisplayedEntries()
            if desc.format == .dmg {
                let roots = (try? newIndex.children(of: "", limit: 100, includeAuxiliary: true, includeDiskImageBackground: true, includeDMGApplicationsShortcut: true)) ?? []
                var apps = roots.filter { $0.path.lowercased().hasSuffix(".app") || $0.name.lowercased().hasSuffix(".app") }
                // Smart subfolder detection: if no .app in root, look for shallow nested .app (e.g. PhotoCraft/PhotoCraft.app)
                if apps.isEmpty, let candidateApps = try? newIndex.findApplicationBundles(limit: 5), !candidateApps.isEmpty {
                    apps = candidateApps
                }
                var hasShortcut = roots.contains { $0.isDMGApplicationsShortcut }
                if !hasShortcut, let app = apps.first {
                    let parent = app.parentPath
                    if !parent.isEmpty, let siblings = try? newIndex.children(of: parent, limit: 50, includeAuxiliary: true, includeDiskImageBackground: true, includeDMGApplicationsShortcut: true) {
                        hasShortcut = siblings.contains { $0.isDMGApplicationsShortcut }
                    }
                }
                self.diskImagePresentation = DiskImagePresentation(
                    rootEntries: roots.filter { !$0.isAuxiliary && !$0.isDiskImageBackground },
                    applicationBundleEntries: apps,
                    hasApplicationsShortcut: hasShortcut
                )
                self.dmgViewMode = apps.isEmpty ? .list : .canvas
                self.dmgAppIcon = nil

                // Extract high-resolution branded .icns for the .app inside the DMG
                if let app = apps.first, let descs = try? newIndex.descendants(of: app.path) {
                    let appCleanPrefix = app.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let infoPlistPath = "\(appCleanPrefix)/Contents/Info.plist"
                    let infoPlistEntry = descs.first(where: { $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == infoPlistPath })
                    let icnsCandidates = descs.filter { $0.name.lowercased().hasSuffix(".icns") }
                    let preferredPrefix = "\(appCleanPrefix)/Contents/Resources/"
                    let defaultIcnsEntry = icnsCandidates.first(where: {
                        $0.path.hasPrefix(preferredPrefix) &&
                        !$0.path.dropFirst(preferredPrefix.count).contains("/")
                    }) ?? icnsCandidates.first

                    if !icnsCandidates.isEmpty {
                        Task {
                            if let lease = try? ManagedWorkFileStore.shared.makeStagingLease(prefix: "dmg_icon") {
                                defer { lease.release() }
                                var targetIcnsEntry = defaultIcnsEntry
                                if let infoPlistEntry {
                                    try? await self.broker.extract(primaryURL, entries: [infoPlistEntry], to: lease.url)
                                    let plistURL = lease.url.appendingPathComponent(infoPlistEntry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                                    if let plistData = try? Data(contentsOf: plistURL),
                                       let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                                       let iconFile = (plist["CFBundleIconFile"] as? String) ?? (plist["CFBundleIconName"] as? String),
                                       !iconFile.isEmpty {
                                        let expectedName = iconFile.lowercased().hasSuffix(".icns") ? iconFile.lowercased() : "\(iconFile.lowercased()).icns"
                                        if let matched = icnsCandidates.first(where: { $0.name.lowercased() == expectedName }) {
                                            targetIcnsEntry = matched
                                        }
                                    }
                                }
                                if let icnsEntry = targetIcnsEntry {
                                    try? await self.broker.extract(primaryURL, entries: [icnsEntry], to: lease.url)
                                    let icnsURL = lease.url.appendingPathComponent(icnsEntry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                                    if let img = NSImage(contentsOf: icnsURL) {
                                        img.size = NSSize(width: 96, height: 96)
                                        await MainActor.run {
                                            self.dmgAppIcon = img
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                self.diskImagePresentation = nil
                self.dmgAppIcon = nil
                self.dmgViewMode = .list
            }
            self.statusMessage = "已加载 \(primaryURL.lastPathComponent) — 共 \(totalIndexedCount) 个条目"
            self.lastLoadError = nil
        } catch {
            guard self.currentOpenTaskID == taskID else { return }
            let errString = error.localizedDescription.lowercased()
            if let engErr = error as? ArchiveEngineError, engErr == .wrongPassword || errString.contains("password") {
                statusMessage = "该归档已加密，请输入解压密码"
                promptForPassword(errorMessage: currentArchivePassword != nil ? "密码错误，请重新输入" : nil) { [weak self] enteredPassword in
                    guard let self = self else { return }
                    self.currentArchivePassword = enteredPassword
                    Task {
                        await self.openArchive(at: rawURL, resetNestedStack: resetNestedStack)
                    }
                }
            } else {
                let msg = "加载失败: \(error.localizedDescription)"
                statusMessage = msg
                lastLoadError = msg
            }
        }

        if self.currentOpenTaskID == taskID {
            isBusy = false
        }
    }

    public func refreshDisplayedEntries() throws {
        guard let index = entryIndex else {
            displayedEntries = []
            totalIndexedCount = 0
            containsNestedArchives = false
            return
        }
        totalIndexedCount = try index.count()

        let isDMG = currentDescriptor?.format == .dmg
        let filterDMG = isDMG && PureZipPreferences.shared.autoFilterDMGAuxiliary
        let includeDMGShortcuts = includeAuxiliary || !filterDMG
        let includeDiskBackground = includeAuxiliary || !filterDMG

        currentChildStats = try index.childStatistics(
            of: currentDirectoryPath,
            treatsDiskImageBackgroundAsAuxiliary: filterDMG,
            treatsDMGApplicationsShortcutAsAuxiliary: filterDMG
        )

        let trimmedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            displayedEntries = try index.page(
                search: trimmedSearch,
                offset: 0,
                limit: 500,
                includeAuxiliary: includeAuxiliary,
                includeDiskImageBackground: includeDiskBackground,
                includeDMGApplicationsShortcut: includeDMGShortcuts
            )
        } else {
            displayedEntries = try index.children(
                of: currentDirectoryPath,
                offset: 0,
                limit: 1000,
                includeAuxiliary: includeAuxiliary,
                includeDiskImageBackground: includeDiskBackground,
                includeDMGApplicationsShortcut: includeDMGShortcuts
            )
            // Smart single-root or missing-root unwrapping:
            // If at root and children is empty while totalIndexedCount > 0, fallback to direct entry search
            if currentDirectoryPath.isEmpty && displayedEntries.isEmpty && totalIndexedCount > 0 {
                let allEntries = (try? index.page(search: "", offset: 0, limit: 1000, includeAuxiliary: includeAuxiliary, includeDiskImageBackground: includeDiskBackground, includeDMGApplicationsShortcut: includeDMGShortcuts)) ?? []
                if !allEntries.isEmpty {
                    let rootSegs = Set(allEntries.compactMap { entry -> String? in
                        let parts = entry.path.split(separator: "/")
                        return parts.count > 1 ? String(parts[0]) : nil
                    })
                    if rootSegs.count == 1, let singleRoot = rootSegs.first {
                        self.currentDirectoryPath = singleRoot
                        displayedEntries = (try? index.children(
                            of: singleRoot,
                            offset: 0,
                            limit: 1000,
                            includeAuxiliary: includeAuxiliary,
                            includeDiskImageBackground: includeDiskBackground,
                            includeDMGApplicationsShortcut: includeDMGShortcuts
                        )) ?? allEntries
                    } else {
                        displayedEntries = allEntries
                    }
                }
            }
        }
        containsNestedArchives = displayedEntries.contains(where: \.isNestedArchive)
    }

    // MARK: - Navigation & Nested Archive Inspection

    public var canNavigateUp: Bool {
        !currentDirectoryPath.isEmpty || !nestedStack.isEmpty
    }

    public func closeArchive() {
        if hasUnsavedChanges && !isCapsuleMode {
            switch PureZipPreferences.shared.deskUnsavedChangesAction {
            case "autoSave":
                Task {
                    await savePendingChanges()
                    performCloseArchive()
                }
                return
            case "discard":
                performCloseArchive()
                return
            default: // "ask"
                let alert = NSAlert()
                alert.messageText = "存在未保存的修改"
                alert.informativeText = "当前归档有未保存的增删改动，是否在关闭前保存？"
                alert.addButton(withTitle: "保存并关闭")
                alert.addButton(withTitle: "放弃修改")
                alert.addButton(withTitle: "取消")
                let resp = alert.runModal()
                if resp == .alertFirstButtonReturn {
                    Task {
                        await savePendingChanges()
                        performCloseArchive()
                    }
                    return
                } else if resp == .alertSecondButtonReturn {
                    performCloseArchive()
                    return
                } else {
                    return
                }
            }
        }
        performCloseArchive()
    }

    /// Mounts the current DMG file with the macOS system DiskImageMounter/hdiutil and exits PureZip handling.
    public func openCurrentDMGWithSystemMounter() {
        guard let url = currentArchiveURL, currentDescriptor?.format == .dmg else { return }
        let dmgPath = url.path

        // Close PureZip's session and release locks
        closeArchive()

        // Hide or close the window if applicable
        MainWindowController.shared.hide()

        // Launch with system DiskImageMounter or hdiutil attach
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "DiskImageMounter", dmgPath]
            do {
                try process.run()
            } catch {
                // Fallback to /usr/bin/hdiutil attach
                let fallback = Process()
                fallback.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                fallback.arguments = ["attach", dmgPath]
                try? fallback.run()
            }
        }
    }

    private func performCloseArchive() {
        previewLoadTask?.cancel()
        previewLoadTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        cleanupActiveMediaTemp()
        self.sessionVideoAutoPlay = PureZipPreferences.shared.deskVideoAutoPlay
        self.sessionVideoLoop = false
        self.sessionAudioAutoPlay = PureZipPreferences.shared.deskAudioAutoPlay
        self.sessionAudioLoop = PureZipPreferences.shared.deskAudioLoop
        self.sessionMediaMuted = PureZipPreferences.shared.deskMediaAlwaysMute

        QuickLookPreviewController.shared.closePreview()
        ArchiveHoverPreviewPanelController.shared.hide()
        currentArchiveURL = nil
        entryIndex?.close()
        entryIndex = nil
        displayedEntries = []
        diskImagePresentation = nil
        dmgAppIcon = nil
        dmgViewMode = .canvas
        selectedEntryID = nil
        selectedEntryPreview = nil
        quickLookItemURL = nil
        hoveredCandidate = nil
        activeNestedLeases.forEach { $0.release() }
        activeNestedLeases.removeAll()
        nestedStack.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        hasUnsavedChanges = false
        entryBeingRenamed = nil
        isShowingRenameSheet = false
        statusMessage = "就绪"
    }

    public func navigateToDirectory(_ path: String) {
        previewLoadTask?.cancel()
        previewLoadTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        cleanupActiveMediaTemp()

        ArchiveHoverPreviewPanelController.shared.hide()
        currentDirectoryPath = ArchiveBrowserProjection.canonicalDirectoryPath(path)
        searchQuery = ""
        selectedEntryID = nil
        selectedEntryPreview = nil
        try? refreshDisplayedEntries()
    }

    @discardableResult
    public func navigateUp() -> Bool {
        if viewMode == .columns && !isCapsuleMode {
            if columnBrowserState.exitToParentColumn(session: self) {
                return true
            }
            if !nestedStack.isEmpty {
                Task { await popNestedArchive() }
                return true
            }
            return false
        }

        guard !currentDirectoryPath.isEmpty else {
            if !nestedStack.isEmpty {
                Task { await popNestedArchive() }
                return true
            }
            return false
        }
        let comps = currentDirectoryPath.split(separator: "/").dropLast()
        navigateToDirectory(comps.joined(separator: "/"))
        return true
    }

    public var breadcrumbComponents: [(title: String, path: String)] {
        var result: [(String, String)] = [(currentArchiveURL?.lastPathComponent ?? "Root", "")]
        guard !currentDirectoryPath.isEmpty else { return result }
        let parts = currentDirectoryPath.split(separator: "/").map(String.init)
        for idx in parts.indices {
            let p = parts[0...idx].joined(separator: "/")
            result.append((parts[idx], p))
        }
        return result
    }

    public func handleDoubleClick(on entry: ArchiveEntry) {
        if entry.path.hasSuffix(".app") || entry.name.hasSuffix(".app") {
            let actions = PureActionsRouter.resolveActions(for: entry)
            if let prime = actions.first(where: { $0.kind == .installApplication }) {
                Task {
                    let msg = try? await PureActionsRouter.execute(action: prime.kind, for: entry, session: self)
                    statusMessage = msg ?? "已安装 \(entry.name)"
                }
                return
            }
        }
        if entry.type == .directory {
            navigateToDirectory(entry.path)
            return
        }
        // Check if entry is a nested archive (.zip, .tar.gz, .7z, .tar, .gz, .bz2, .xz)
        let dummyURL = URL(fileURLWithPath: "/tmp/\(entry.name)")
        let detected = ArchiveFormatDescriptor.detect(at: dummyURL)
        if detected.format != .unknown {
            Task { await openNestedArchive(entry: entry) }
        } else {
            Task { await loadEntryPreview(for: entry) }
        }
    }

    public func openNestedArchive(entry: ArchiveEntry) async {
        guard let parentURL = currentArchiveURL else { return }
        isBusy = true
        statusMessage = "正在展开嵌套归档: \(entry.name)..."
        do {
            let lease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "nested")
            activeNestedLeases.append(lease)
            try await broker.extract(parentURL, entries: [entry], to: lease.url)
            var nestedFileURL = lease.url.appendingPathComponent(entry.path)
            if !FileManager.default.fileExists(atPath: nestedFileURL.path) {
                let stripped = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let alt = lease.url.appendingPathComponent(stripped)
                if FileManager.default.fileExists(atPath: alt.path) {
                    nestedFileURL = alt
                } else if let enumerator = FileManager.default.enumerator(at: lease.url, includingPropertiesForKeys: nil) {
                    while let item = enumerator.nextObject() {
                        if let obj = item as? URL, obj.lastPathComponent == entry.name {
                            nestedFileURL = obj
                            break
                        }
                    }
                }
            }
            guard FileManager.default.fileExists(atPath: nestedFileURL.path) else {
                throw ArchiveEngineError.io("无法提取嵌套归档条目 \(entry.path)")
            }

            nestedStack.append(NestedArchiveCrumb(
                archiveURL: parentURL,
                displayName: parentURL.lastPathComponent,
                directoryPath: currentDirectoryPath,
                workLease: lease
            ))
            await openArchive(at: nestedFileURL, resetNestedStack: false)
        } catch {
            statusMessage = "展开嵌套归档失败: \(error.localizedDescription)"
        }
        isBusy = false
    }

    public func popNestedArchive() async {
        guard !nestedStack.isEmpty else { return }
        await popToNestedArchive(at: nestedStack.count - 1)
    }

    public func popToNestedArchive(at index: Int, directoryPath: String? = nil) async {
        guard nestedStack.indices.contains(index) else { return }
        let targetCrumb = nestedStack[index]
        let removedCrumbs = Array(nestedStack[index...])
        nestedStack.removeSubrange(index...)
        await openArchive(at: targetCrumb.archiveURL, resetNestedStack: false)
        navigateToDirectory(directoryPath ?? targetCrumb.directoryPath)
        for crumb in removedCrumbs {
            if let lease = crumb.workLease {
                lease.release()
                activeNestedLeases.removeAll { $0 === lease }
            }
        }
    }

    // MARK: - Live Inspector & Preview

    public func selectEntry(_ entry: ArchiveEntry?) {
        previewLoadTask?.cancel()
        previewLoadTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        cleanupActiveMediaTemp()
        isLoadingEntryPreview = false

        selectedEntryID = entry?.id
        guard let entry else {
            selectedEntryPreview = nil
            return
        }
        QuickLookPreviewController.shared.updatePreviewIfVisible(for: entry, session: self)
        previewLoadTask = Task { await loadEntryPreview(for: entry) }
        prefetchNeighbors(around: entry)
    }

    private func prefetchNeighbors(around entry: ArchiveEntry) {
        guard let archiveURL = currentArchiveURL else { return }

        // Find candidate neighbor entries in current view context
        let currentList: [ArchiveEntry] = {
            if viewMode == .columns && !isCapsuleMode {
                let colIdx = max(0, min(columnBrowserState.focusedColumnIndex, columnBrowserState.columnNodes.count - 1))
                if colIdx < columnBrowserState.columnNodes.count {
                    return columnBrowserState.columnNodes[colIdx].entries
                }
            }
            return displayedEntries
        }()

        guard let curIdx = currentList.firstIndex(where: { $0.id == entry.id }) else { return }

        var candidates: [ArchiveEntry] = []
        if curIdx + 1 < currentList.count {
            candidates.append(currentList[curIdx + 1])
        }
        if curIdx > 0 {
            candidates.append(currentList[curIdx - 1])
        }
        if curIdx + 2 < currentList.count {
            candidates.append(currentList[curIdx + 2])
        }

        let broker = self.broker
        prefetchTask = Task.detached(priority: .utility) {
            for cand in candidates {
                guard !Task.isCancelled else { break }
                guard cand.type == .file else { continue }
                let ext = (cand.name as NSString).pathExtension.lowercased()
                let isVid = MediaPreviewExtractor.isVideo(ext: ext)
                let isImg = ImagePreviewHelper.isSupportedImage(ext: ext)
                guard isVid || isImg else { continue }

                let key = "\(archiveURL.path):\(cand.path)"
                if isVid && PreviewArtifactCache.shared.videoData(for: key) != nil { continue }
                if isImg && PreviewArtifactCache.shared.image(for: key) != nil { continue }

                do {
                    let extracted = try await PreviewArtifactCache.shared.sharedExtractedFile(for: cand, in: archiveURL, broker: broker)
                    guard !Task.isCancelled else { break }
                    if isVid {
                        let vData = await MediaPreviewExtractor.extractVideoData(
                            from: extracted,
                            maxKeyframes: 4,
                            targetSize: CGSize(width: 360, height: 202)
                        )
                        PreviewArtifactCache.shared.setVideoData(vData, for: key)
                    } else if isImg {
                        if let thumb = ImagePreviewHelper.createThumbnail(at: extracted, maxPixelSize: 1200) {
                            PreviewArtifactCache.shared.setImage(thumb, for: key)
                        }
                    }
                } catch {
                    // Pre-fetching is best-effort
                }
            }
        }
    }

    // MARK: - Keyboard Navigation

    public enum NavigationDirection: Sendable {
        case up
        case down
        case left
        case right
    }

    @discardableResult
    public func navigateSelection(_ direction: NavigationDirection) -> Bool {
        guard currentArchiveURL != nil else { return false }

        if viewMode == .columns && !isCapsuleMode {
            return columnBrowserState.navigate(direction: direction, session: self)
        }

        let entries = displayedEntries
        guard !entries.isEmpty else { return false }

        let currentIndex = entries.firstIndex(where: { $0.id == selectedEntryID })

        if isCapsuleMode || viewMode == .list {
            switch direction {
            case .up:
                let target = currentIndex.map { max(0, $0 - 1) } ?? (entries.count - 1)
                selectEntry(entries[target])
                return true
            case .down:
                let target = currentIndex.map { min(entries.count - 1, $0 + 1) } ?? 0
                selectEntry(entries[target])
                return true
            case .left, .right:
                // Scheme B: Direction keys do NOT change hierarchy!
                return false
            }
        } else if viewMode == .icons {
            let cols = max(1, gridColumnCount)
            switch direction {
            case .right:
                // Move to next entry; when at end of row, wraps to start of next row
                let target = currentIndex.map { min(entries.count - 1, $0 + 1) } ?? 0
                selectEntry(entries[target])
                return true
            case .left:
                // Move to previous entry; when at start of row, wraps to end of previous row
                if let idx = currentIndex {
                    if idx > 0 {
                        selectEntry(entries[idx - 1])
                        return true
                    }
                    // At boundary index 0, stop at boundary. Direction keys do NOT change hierarchy!
                    return false
                } else {
                    selectEntry(entries.first)
                    return true
                }
            case .down:
                // Move down by one row (index + columnCount)
                let target = currentIndex.map { min(entries.count - 1, $0 + cols) } ?? 0
                selectEntry(entries[target])
                return true
            case .up:
                // Move up by one row (index - columnCount)
                let target = currentIndex.map { max(0, $0 - cols) } ?? 0
                selectEntry(entries[target])
                return true
            }
        }
        return false
    }

    @discardableResult
    public func activateSelectedEntry() -> Bool {
        if viewMode == .columns && !isCapsuleMode {
            if let entry = columnBrowserState.activeEntry {
                if entry.type == .directory {
                    if columnBrowserState.enterChildColumn(session: self) {
                        return true
                    }
                }
                handleDoubleClick(on: entry)
                return true
            }
            return false
        }
        if let selID = selectedEntryID, let entry = displayedEntries.first(where: { $0.id == selID }) {
            handleDoubleClick(on: entry)
            return true
        }
        return false
    }

    private func cleanupActiveMediaTemp() {
        if let temp = activeMediaTempURL {
            try? FileManager.default.removeItem(at: temp)
            activeMediaTempURL = nil
        }
    }

    public func loadEntryPreview(for entry: ArchiveEntry) async {
        guard !Task.isCancelled, selectedEntryID == entry.id else { return }
        guard let archiveURL = currentArchiveURL else { return }
        if entry.type == .directory {
            isLoadingEntryPreview = false
            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: "",
                hexPreview: "",
                image: nil,
                classifierDecision: nil
            )
            return
        }
        // Cap live preview extraction: Media up to 2 GiB (with fast low-res frame & audio sampling), Nested Archives up to 500 MiB, Images/RAW up to 200 MiB, documents/text up to 15 MiB
        let ext = (entry.name as NSString).pathExtension.lowercased()
        let isMedia = MediaPreviewExtractor.isAudio(ext: ext) || MediaPreviewExtractor.isVideo(ext: ext)
        let isNested = entry.isNestedArchive
        let isImage = ImagePreviewHelper.isSupportedImage(ext: ext)
        let maxLimit: Int64
        if isMedia {
            maxLimit = 2 * 1024 * 1024 * 1024
        } else if isNested {
            maxLimit = 500 * 1024 * 1024
        } else if isImage {
            maxLimit = 200 * 1024 * 1024
        } else {
            maxLimit = 15 * 1024 * 1024
        }

        guard entry.uncompressedSize <= maxLimit else {
            isLoadingEntryPreview = false
            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: "文件较大 (\(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file)))，请按空格键快速预览或解压后查看。",
                hexPreview: "",
                image: nil,
                classifierDecision: nil
            )
            return
        }

        let cacheKey = "\(archiveURL.path):\(entry.path)"
        if isNested, let cachedSummary = PreviewArtifactCache.shared.nestedArchiveSummary(for: cacheKey) {
            guard !Task.isCancelled, selectedEntryID == entry.id else { return }
            isLoadingEntryPreview = false
            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: nil,
                hexPreview: "",
                image: nil,
                classifierDecision: nil,
                nestedArchiveSummary: cachedSummary
            )
            return
        } else if !isMedia, let cachedImg = PreviewArtifactCache.shared.image(for: cacheKey) {
            guard !Task.isCancelled, selectedEntryID == entry.id else { return }
            isLoadingEntryPreview = false
            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: nil,
                hexPreview: "",
                image: cachedImg,
                classifierDecision: nil
            )
            return
        } else if let cachedPages = PreviewArtifactCache.shared.pdfPages(for: cacheKey), let firstPage = cachedPages.first {
            guard !Task.isCancelled, selectedEntryID == entry.id else { return }
            isLoadingEntryPreview = false
            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: nil,
                hexPreview: "",
                image: firstPage,
                classifierDecision: nil
            )
            return
        } else if let cachedText = PreviewArtifactCache.shared.text(for: cacheKey) {
            guard !Task.isCancelled, selectedEntryID == entry.id else { return }
            isLoadingEntryPreview = false
            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: cachedText,
                hexPreview: "",
                image: nil,
                classifierDecision: nil
            )
            return
        }

        isLoadingEntryPreview = true
        defer {
            if selectedEntryID == entry.id {
                isLoadingEntryPreview = false
            }
        }

        do {
            let extractedURL = try await PreviewArtifactCache.shared.sharedExtractedFile(
                for: entry,
                in: archiveURL,
                broker: broker
            )

            guard !Task.isCancelled, selectedEntryID == entry.id else { return }

            if isNested, let nestedDesc = entry.nestedArchiveDescriptor {
                var nestedEntries: [ArchiveEntry] = []
                var totalBytes: Int64 = 0
                if let stream = try? await broker.list(extractedURL, password: nil) {
                    for try await batch in stream {
                        for item in batch where !item.isAuxiliary {
                            nestedEntries.append(item)
                            if item.type == .file {
                                totalBytes += max(0, item.uncompressedSize)
                            }
                        }
                    }
                }
                let summary = NestedArchivePreviewSummary(
                    formatDisplayName: nestedDesc.displayName,
                    totalEntryCount: nestedEntries.count,
                    totalUncompressedBytes: totalBytes,
                    topEntries: Array(nestedEntries.prefix(12))
                )
                PreviewArtifactCache.shared.setNestedArchiveSummary(summary, for: cacheKey)
                let decision = SmartCompressionClassifier.classify(fileAt: extractedURL, compressionLevel: 6)
                let headerData = (try? FileHandle(forReadingFrom: extractedURL))?.readData(ofLength: 256) ?? Data()
                let hex = headerData.map { String(format: "%02X", $0) }.joined(separator: " ")

                guard !Task.isCancelled, selectedEntryID == entry.id else { return }
                selectedEntryPreview = SelectedEntryPreview(
                    entry: entry,
                    textContent: nil,
                    hexPreview: hex,
                    image: nil,
                    classifierDecision: decision,
                    nestedArchiveSummary: summary
                )
                return
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: extractedURL.path)[.size] as? Int64) ?? entry.uncompressedSize
            let sampleCap = isMedia ? 256 : (10 * 1024 * 1024) // Only read 256B header for media, 10MB cap for text/hex
            let data: Data
            if fileSize > Int64(sampleCap) {
                if let fh = try? FileHandle(forReadingFrom: extractedURL) {
                    data = fh.readData(ofLength: sampleCap)
                    try? fh.close()
                } else {
                    data = Data()
                }
            } else {
                guard let loaded = try? Data(contentsOf: extractedURL) else { return }
                data = loaded
            }
            guard !Task.isCancelled, selectedEntryID == entry.id else { return }

            let decision = SmartCompressionClassifier.classify(fileAt: extractedURL, compressionLevel: 6)
            var image: NSImage? = nil
            if !isMedia {
                if isImage {
                    image = ImagePreviewHelper.createThumbnail(at: extractedURL, maxPixelSize: 1600)
                } else {
                    image = NSImage(contentsOf: extractedURL)
                }
            }

            if image == nil, ext == "pdf",
               let pdfDoc = PDFDocument(url: extractedURL),
               let page = pdfDoc.page(at: 0) {
                image = renderHighResolutionPDFPage(page, targetWidth: 1200)
            }

            // Media support (Video & Audio Player) using shared cached file directly (zero duplicate copy)
            var mediaFileURL: URL? = nil
            var videoMetadata: VideoPreviewData? = nil
            var audioMetadata: AudioPreviewData? = nil

            if MediaPreviewExtractor.isVideo(ext: ext) {
                mediaFileURL = extractedURL
                if let cachedV = PreviewArtifactCache.shared.videoData(for: cacheKey) {
                    videoMetadata = cachedV
                    image = cachedV.keyframes.first
                } else {
                    let vData = await MediaPreviewExtractor.extractVideoData(
                        from: extractedURL,
                        maxKeyframes: 4,
                        targetSize: CGSize(width: 360, height: 202)
                    )
                    PreviewArtifactCache.shared.setVideoData(vData, for: cacheKey)
                    videoMetadata = vData
                    image = vData.keyframes.first
                }
            } else if MediaPreviewExtractor.isAudio(ext: ext) {
                mediaFileURL = extractedURL
                if let cachedA = PreviewArtifactCache.shared.audioData(for: cacheKey) {
                    audioMetadata = cachedA
                    image = cachedA.artwork
                } else {
                    let aData = await MediaPreviewExtractor.extractAudioData(from: extractedURL, sampleCount: 60)
                    PreviewArtifactCache.shared.setAudioData(aData, for: cacheKey)
                    audioMetadata = aData
                    image = aData.artwork
                }
            }

            // 3D Model support (GLB / GLTF / OBJ / DAE / USDZ / STL / PLY / ABC / SCN)
            var modelURL: URL? = nil
            if ["glb", "gltf", "obj", "dae", "usdz", "usd", "scn", "stl", "ply", "abc"].contains(ext) {
                modelURL = extractedURL
            }

            // Generate thumbnail for Office & Keynote documents
            if image == nil && ["docx", "xlsx", "pptx", "pages", "numbers", "key"].contains(ext) {
                let req = QLThumbnailGenerator.Request(
                    fileAt: extractedURL,
                    size: CGSize(width: 512, height: 512),
                    scale: NSScreen.main?.backingScaleFactor ?? 2.0,
                    representationTypes: .all
                )
                let (rep, _) = await withCheckedContinuation { continuation in
                    QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, err in
                        continuation.resume(returning: (rep, err))
                    }
                }
                if let qlImg = rep?.nsImage {
                    image = qlImg
                }
            }

            var text: String? = nil
            if image == nil && modelURL == nil && mediaFileURL == nil {
                let sample = data.prefix(32 * 1024)
                text = String(data: sample, encoding: .utf8) ??
                       String(data: sample, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
            }

            let hex = data.prefix(256).map { String(format: "%02X", $0) }.joined(separator: " ")

            if let img = image {
                PreviewArtifactCache.shared.setImage(img, for: cacheKey)
            } else if let txt = text {
                PreviewArtifactCache.shared.setText(txt, for: cacheKey)
            }

            guard !Task.isCancelled, selectedEntryID == entry.id else { return }

            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: text,
                hexPreview: hex,
                image: image,
                classifierDecision: decision,
                model3DURL: modelURL,
                mediaFileURL: mediaFileURL,
                audioMetadata: audioMetadata,
                videoMetadata: videoMetadata
            )
        } catch {
            guard !Task.isCancelled, selectedEntryID == entry.id else { return }
            selectedEntryPreview = SelectedEntryPreview(
                entry: entry,
                textContent: "预览加载失败: \(error.localizedDescription)",
                hexPreview: "",
                image: nil,
                classifierDecision: nil
            )
        }
    }

    // MARK: - Native QuickLook Integration (Spacebar / 预览按钮)

    public func toggleQuickLookForSelected() {
        guard let found = selectedEntryPreview?.entry ?? (selectedEntryID.flatMap { selID in displayedEntries.first(where: { $0.id == selID }) ?? (try? entryIndex?.entry(forID: selID)) }) else {
            QuickLookPreviewController.shared.closePreview()
            return
        }
        QuickLookPreviewController.shared.togglePreview(for: found, session: self)
    }

    public func presentSystemQuickLook(for entry: ArchiveEntry) async {
        await QuickLookPreviewController.shared.prepareAndShow(entry: entry, session: self)
    }

    // MARK: - Extract, Create, Update, Test & Sample Archive Generator

    /// Clean extraction folder name (e.g. `a.zip` -> `a`, `backup.7z.001` -> `backup`)
    public var suggestedExtractionFolderName: String {
        guard let url = currentArchiveURL else { return "解压文件" }
        return ArchiveVolumeFamily.extractionFolderStem(for: url)
    }

    /// Base directory on the user's disk corresponding to the outermost archive in the nested stack
    public var outermostArchiveDirectoryURL: URL? {
        if let rootCrumb = nestedStack.first {
            return rootCrumb.archiveURL.deletingLastPathComponent()
        }
        return currentArchiveURL?.deletingLastPathComponent()
    }

    /// Extracts all entries to a dedicated subfolder named after the archive stem (e.g. `a.zip` -> `parent/a/`)
    public func extractToNamedSubfolder(expandNestedArchives: Bool = false) async {
        guard let parentDir = outermostArchiveDirectoryURL else { return }
        let stem = suggestedExtractionFolderName
        let targetDir = parentDir.appendingPathComponent(stem, isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        await extractArchive(entries: [], to: targetDir, expandNestedArchives: expandNestedArchives)
    }

    /// Extracts all entries directly into the parent directory alongside the archive (flat)
    public func extractToCurrentDirectory(expandNestedArchives: Bool = false) async {
        guard let parentDir = outermostArchiveDirectoryURL else { return }
        await extractArchive(entries: [], to: parentDir, expandNestedArchives: expandNestedArchives)
    }

    /// Prompts user to select a destination directory via NSOpenPanel (attaches as Sheet if PureDesk is active)
    public func extractToCustomDestination(expandNestedArchives: Bool = false) {
        guard let parentDir = outermostArchiveDirectoryURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = expandNestedArchives ? "解压并展开内部压缩包到此处" : "解压到此处"
        panel.directoryURL = parentDir

        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized && $0.title == "PureZip" }) {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self = self, response == .OK, let selectedURL = panel.url else { return }
                Task {
                    await self.extractArchive(entries: [], to: selectedURL, expandNestedArchives: expandNestedArchives)
                }
            }
        } else {
            if panel.runModal() == .OK, let selectedURL = panel.url {
                Task {
                    await self.extractArchive(entries: [], to: selectedURL, expandNestedArchives: expandNestedArchives)
                }
            }
        }
    }

    /// Extracts a nested archive entry from the current archive and immediately unpacks its internal contents into a named folder alongside the parent archive
    public func extractNestedArchiveEntryDirectly(_ entry: ArchiveEntry) async {
        guard let archiveURL = currentArchiveURL,
              let parentDir = outermostArchiveDirectoryURL else { return }
        isBusy = true
        progressFraction = nil
        statusMessage = "正在直接解压内部压缩包: \(entry.name)..."
        do {
            let extractedArchiveURL = try await PreviewArtifactCache.shared.sharedExtractedFile(
                for: entry,
                in: archiveURL,
                broker: broker
            )
            let stem = ArchiveVolumeFamily.extractionFolderStem(for: URL(fileURLWithPath: entry.name))
            let targetDir = ArchiveOutputFamily.collisionFreeBaseURL(
                for: parentDir.appendingPathComponent(stem, isDirectory: true)
            )
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "extract-nested-direct")
            defer { stageLease.release() }

            try await broker.extract(extractedArchiveURL, entries: [], to: stageLease.url, password: nil)
            _ = await recursivelyExpandNestedArchives(in: stageLease.url, maxDepth: 2)

            let excludeAux = PureZipPreferences.shared.autoExcludeSystemAuxiliary
            let manifest = try ExtractionFinalizationManifest.prepare(
                stagingDirectory: stageLease.url,
                shouldRemove: excludeAux ? nil : { _ in false }
            )
            var collisionIndex = DestinationCollisionIndex()
            let published = try FinderExtractionPublisher.publishMergingContents(
                using: manifest,
                to: targetDir,
                collisionIndex: &collisionIndex,
                directoryConflictPolicy: .rename
            )
            statusMessage = "已直接解压内部压缩包「\(entry.name)」(\(published.count) 项) 至 \(targetDir.lastPathComponent)/"
            NSWorkspace.shared.activateFileViewerSelecting([targetDir])
        } catch {
            statusMessage = "解压内部压缩包失败: \(error.localizedDescription)"
        }
        isBusy = false
    }

    /// Recursively expands nested archives inside a directory up to `maxDepth` levels, replacing each nested archive with its extracted folder
    public func recursivelyExpandNestedArchives(in rootDirectory: URL, maxDepth: Int = 3) async -> Int {
        var expandedTotal = 0
        let fm = FileManager.default
        let skipExtensions: Set<String> = ["app", "framework", "bundle", "plugin", "qlgenerator", "appex", "jar", "war", "ear", "apk", "ipa", "xpi", "crx", "docx", "xlsx", "pptx", "pages", "numbers", "key", "epub", "dmg", "iso", "pkg"]

        for depth in 0..<maxDepth {
            guard let enumerator = fm.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { break }

            var candidates: [URL] = []
            while let obj = enumerator.nextObject() as? URL {
                let ext = obj.pathExtension.lowercased()
                if skipExtensions.contains(ext) {
                    continue
                }
                let isRegular = (try? obj.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isRegular else { continue }
                let desc = ArchiveFormatDescriptor.detect(at: obj)
                if desc.format != .unknown && desc.format != .dmg && desc.format != .iso {
                    candidates.append(obj)
                }
            }

            if candidates.isEmpty {
                break
            }

            var expandedInPass = 0
            for nestedURL in candidates {
                let stem = ArchiveVolumeFamily.extractionFolderStem(for: nestedURL)
                let parent = nestedURL.deletingLastPathComponent()
                var destSubdir = parent.appendingPathComponent(stem, isDirectory: true)
                if destSubdir.standardizedFileURL == nestedURL.standardizedFileURL {
                    destSubdir = parent.appendingPathComponent("\(stem)_extracted", isDirectory: true)
                }
                await MainActor.run {
                    self.statusMessage = "正在递归展开第 \(depth + 1) 层内部压缩包: \(nestedURL.lastPathComponent)..."
                }
                do {
                    try fm.createDirectory(at: destSubdir, withIntermediateDirectories: true)
                    try await broker.extract(nestedURL, entries: [], to: destSubdir, password: nil)
                    try? fm.removeItem(at: nestedURL)
                    expandedInPass += 1
                    expandedTotal += 1
                } catch {
                    // Keep original nested archive intact if it is password-protected or fails to extract
                    continue
                }
            }

            if expandedInPass == 0 {
                break
            }
        }
        return expandedTotal
    }

    public func extractArchive(
        entries: [ArchiveEntry] = [],
        to destinationDir: URL,
        expandNestedArchives: Bool = false
    ) async {
        guard let archiveURL = currentArchiveURL else { return }
        isBusy = true
        progressFraction = 0.0
        statusMessage = expandNestedArchives
            ? "正在解压 \(archiveURL.lastPathComponent) 并准备递归展开内部压缩包..."
            : "正在解压 \(archiveURL.lastPathComponent)..."

        do {
            let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "extract")
            defer { stageLease.release() }

            try await broker.extract(
                archiveURL,
                entries: entries,
                to: stageLease.url,
                password: currentArchivePassword
            ) { [weak self] prog in
                Task { @MainActor in
                    if let total = prog.total, total > 0 {
                        self?.progressFraction = Double(prog.completed) / Double(total)
                    }
                }
            }

            var expandedNestedCount = 0
            if expandNestedArchives {
                expandedNestedCount = await recursivelyExpandNestedArchives(in: stageLease.url, maxDepth: 3)
            }

            let excludeAux = PureZipPreferences.shared.autoExcludeSystemAuxiliary
            let manifest = try ExtractionFinalizationManifest.prepare(
                stagingDirectory: stageLease.url,
                shouldRemove: excludeAux ? nil : { _ in false }
            )
            var collisionIndex = DestinationCollisionIndex()
            let published = try FinderExtractionPublisher.publishMergingContents(
                using: manifest,
                to: destinationDir,
                collisionIndex: &collisionIndex,
                directoryConflictPolicy: .rename
            )
            if expandedNestedCount > 0 {
                statusMessage = "解压完成: 共输出 \(published.count) 个顶层项至 \(destinationDir.path) (已递归展开 \(expandedNestedCount) 个内部压缩包)"
            } else {
                statusMessage = "解压完成: 共输出 \(published.count) 个顶层项至 \(destinationDir.path) (已过滤 \(manifest.filteredItemCount) 项 macOS 噪音元数据)"
            }
            NSWorkspace.shared.activateFileViewerSelecting(published)

            // Post-extraction archive handling based on Preferences (only when extracting outermost archive)
            if nestedStack.isEmpty {
                switch PureZipPreferences.shared.extractionPostAction {
                case "移入废纸篓":
                    NSWorkspace.shared.recycle([archiveURL]) { _, _ in }
                case "每次均询问":
                    let alert = NSAlert()
                    alert.messageText = "全部解压完成"
                    alert.informativeText = "归档内容已成功解压至 \"\(destinationDir.lastPathComponent)\"。是否将原压缩包移入废纸篓？"
                    alert.addButton(withTitle: "保留压缩包")
                    alert.addButton(withTitle: "移入废纸篓")
                    if alert.runModal() == .alertSecondButtonReturn {
                        NSWorkspace.shared.recycle([archiveURL]) { _, _ in }
                    }
                default:
                    break
                }
            }

            // Auto-close window if enabled
            if PureZipPreferences.shared.autoCloseAfterExtraction {
                self.closeArchive()
                MainWindowController.shared.hide()
            }
        } catch {
            let errString = error.localizedDescription.lowercased()
            if let engErr = error as? ArchiveEngineError, engErr == .wrongPassword || errString.contains("password") {
                statusMessage = "解压需要密码"
                promptForPassword(errorMessage: currentArchivePassword != nil ? "密码错误，请重新输入" : nil) { [weak self] enteredPassword in
                    guard let self = self else { return }
                    self.currentArchivePassword = enteredPassword
                    Task {
                        await self.extractArchive(entries: entries, to: destinationDir, expandNestedArchives: expandNestedArchives)
                    }
                }
            } else {
                statusMessage = "解压失败: \(error.localizedDescription)"
            }
        }
        progressFraction = nil
        isBusy = false
    }

    /// Directly extracts an archive to a specified directory without loading it into the main browser window.
    public func extractArchiveDirectly(
        archiveURL: URL,
        to destinationDir: URL,
        expandNestedArchives: Bool = false,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> [URL] {
        let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "extract-direct")
        defer { stageLease.release() }

        try await broker.extract(
            archiveURL,
            entries: [],
            to: stageLease.url,
            password: nil
        ) { prog in
            if let total = prog.total, total > 0 {
                let fraction = Double(prog.completed) / Double(total)
                Task { @MainActor in
                    onProgress?(fraction)
                }
            }
        }

        if expandNestedArchives {
            _ = await recursivelyExpandNestedArchives(in: stageLease.url, maxDepth: 3)
        }

        let excludeAux = PureZipPreferences.shared.autoExcludeSystemAuxiliary
        let manifest = try ExtractionFinalizationManifest.prepare(
            stagingDirectory: stageLease.url,
            shouldRemove: excludeAux ? nil : { _ in false }
        )
        var collisionIndex = DestinationCollisionIndex()
        let published = try FinderExtractionPublisher.publishMergingContents(
            using: manifest,
            to: destinationDir,
            collisionIndex: &collisionIndex,
            directoryConflictPolicy: .rename
        )
        NSWorkspace.shared.activateFileViewerSelecting(published)
        return published
    }

    /// Directly creates a zip/7z archive to a destination URL without loading it into the main browser window.
    public func createArchiveDirectly(
        sources: [URL],
        destinationURL: URL,
        format: ArchiveFormat = .zip,
        level: Int = 6,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard !sources.isEmpty else {
            throw FinderActionError.emptySelection
        }
        let registry = try ManagedTemporaryArtifactRegistry()
        let lease = try await registry.reserveArchivePublication(finalURL: destinationURL)
        do {
            let profile = CompressionProfile(format: format, level: level)
            try await broker.create(
                sources: sources,
                at: lease.stagedPrimaryURL,
                profile: profile
            ) { prog in
                if let total = prog.total, total > 0 {
                    let fraction = Double(prog.completed) / Double(total)
                    Task { @MainActor in
                        onProgress?(fraction)
                    }
                }
            }
            let result = try await lease.commit()
            NSWorkspace.shared.activateFileViewerSelecting([result.primaryURL])
            return result.primaryURL
        } catch {
            await lease.rollbackAndWait()
            throw error
        }
    }

    public func createArchive(sources: [URL], destinationURL: URL, format: ArchiveFormat, level: Int = 6) async {
        guard !sources.isEmpty else { return }
        isBusy = true
        progressFraction = 0.0
        statusMessage = "正在事务性创建归档 \(destinationURL.lastPathComponent)..."

        do {
            let registry = try ManagedTemporaryArtifactRegistry()
            let lease = try await registry.reserveArchivePublication(finalURL: destinationURL)
            do {
                let profile = CompressionProfile(format: format, level: level)
                try await broker.create(
                    sources: sources,
                    at: lease.stagedPrimaryURL,
                    profile: profile
                ) { [weak self] prog in
                    Task { @MainActor in
                        if let total = prog.total, total > 0 {
                            self?.progressFraction = Double(prog.completed) / Double(total)
                        }
                    }
                }
                let result = try await lease.commit()
                statusMessage = "成功创建并原子提交归档: \(result.primaryURL.path)"
                await openArchive(at: result.primaryURL)
            } catch {
                await lease.rollbackAndWait()
                throw error
            }
        } catch {
            statusMessage = "创建归档失败: \(error.localizedDescription)"
        }
        progressFraction = nil
        isBusy = false
    }

    // MARK: - Staged Archive Editing, In-Archive Rename & Undo/Redo Engine

    public func stageDeleteSelected() {
        if isCapsuleMode && !PureZipPreferences.shared.capsuleWindowAllowEditing {
            statusMessage = "当前 Pure Capsule 浮窗处于只读模式（可在设置中开启编辑权限）"
            return
        }
        guard let found = selectedEntryPreview?.entry ?? (selectedEntryID.flatMap { selID in displayedEntries.first(where: { $0.id == selID }) ?? (try? entryIndex?.entry(forID: selID)) }) else { return }
        stageDelete(entries: [found])
    }

    public func stageDelete(entries: [ArchiveEntry], autoSaveIfCapsule: Bool = true) {
        guard !isBusy, !entries.isEmpty else { return }
        if isCapsuleMode && !PureZipPreferences.shared.capsuleWindowAllowEditing {
            statusMessage = "当前 Pure Capsule 浮窗处于只读模式（可在设置中开启编辑权限）"
            return
        }
        for entry in entries {
            undoStack.append(.delete(entry: entry))
            try? entryIndex?.remove(canonicalPaths: [entry.canonicalPath])
        }
        redoStack.removeAll()
        hasUnsavedChanges = true
        indexRevision += 1
        selectedEntryID = nil
        selectedEntryPreview = nil
        try? refreshDisplayedEntries()
        statusMessage = "已从归档中删除 \(entries.count) 个项目"

        if autoSaveIfCapsule && isCapsuleMode && PureZipPreferences.shared.capsuleWindowAllowEditing {
            Task {
                await savePendingChanges(completionMessage: "已删除并自动保存修改")
            }
        }
    }

    public func stageRename(entry: ArchiveEntry, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != entry.name else { return }
        let oldCanonical = entry.canonicalPath
        let parent = entry.parentPath
        let newPath = parent.isEmpty ? trimmed : "\(parent)/\(trimmed)"
        let newCanonical = ArchiveBrowserProjection.canonicalDirectoryPath(newPath)

        let newEntry = ArchiveEntry(
            id: newCanonical,
            path: newPath,
            type: entry.type,
            uncompressedSize: entry.uncompressedSize,
            compressedSize: entry.compressedSize,
            modifiedAt: Date(),
            permissions: entry.permissions,
            checksum: entry.checksum,
            encrypted: entry.encrypted,
            linkTarget: entry.linkTarget,
            duplicateRecordCount: entry.duplicateRecordCount
        )

        undoStack.append(.rename(originalEntry: entry, newEntry: newEntry))
        redoStack.removeAll()
        hasUnsavedChanges = true
        indexRevision += 1

        try? entryIndex?.rename(oldCanonicalPath: oldCanonical, to: newEntry)
        try? refreshDisplayedEntries()
        selectedEntryID = newEntry.id
        statusMessage = "已将「\(entry.name)」重命名为「\(trimmed)」(可按 ⌘Z 撤销)"
    }

    private func makeUniqueName(originalName: String, existingNames: Set<String>) -> String {
        if !existingNames.contains(originalName) {
            return originalName
        }

        let ext = (originalName as NSString).pathExtension
        let baseName = (originalName as NSString).deletingPathExtension

        var rawBase = baseName
        if let match = rawBase.range(of: #" 副本( \d+)?$"#, options: .regularExpression) {
            rawBase = String(rawBase[..<match.lowerBound])
        }

        var counter = 1
        while true {
            let suffix = counter == 1 ? " 副本" : " 副本 \(counter)"
            let candidate = ext.isEmpty ? "\(rawBase)\(suffix)" : "\(rawBase)\(suffix).\(ext)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    public func stageAdd(urls: [URL]) {
        guard !urls.isEmpty else { return }

        let existingChildren = (try? entryIndex?.children(of: currentDirectoryPath, limit: 10000, includeAuxiliary: true)) ?? []
        var existingNames = Set(existingChildren.map(\.name))

        var allStagedEntries: [ArchiveEntry] = []

        for url in urls {
            let originalFilename = url.lastPathComponent
            var shouldOverwrite = false

            if existingNames.contains(originalFilename) && !isCapsuleMode && PureZipPreferences.shared.deskDuplicateNamingAction == "ask" {
                let alert = NSAlert()
                alert.messageText = "存在同名文件"
                alert.informativeText = "归档中已存在名为「\(originalFilename)」的项目。是否替换原文件？"
                alert.addButton(withTitle: "替换覆盖")
                alert.addButton(withTitle: "保留双方 (重命名为副本)")
                alert.addButton(withTitle: "跳过")
                let resp = alert.runModal()
                if resp == .alertFirstButtonReturn {
                    shouldOverwrite = true
                } else if resp == .alertThirdButtonReturn {
                    continue
                }
            }

            let uniqueFilename: String
            if shouldOverwrite {
                uniqueFilename = originalFilename
                let existingPath = currentDirectoryPath.isEmpty ? uniqueFilename : "\(currentDirectoryPath)/\(uniqueFilename)"
                let canonical = ArchiveBrowserProjection.canonicalDirectoryPath(existingPath)
                try? entryIndex?.remove(canonicalPaths: [canonical])
            } else {
                uniqueFilename = makeUniqueName(originalName: originalFilename, existingNames: existingNames)
                existingNames.insert(uniqueFilename)
            }

            let targetPath = currentDirectoryPath.isEmpty ? uniqueFilename : "\(currentDirectoryPath)/\(uniqueFilename)"
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let entryType: ArchiveEntryType = isDir.boolValue ? .directory : .file

            let effectiveSourceURL: URL
            if uniqueFilename != originalFilename {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PureZipDuplicates", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let copyURL = tempDir.appendingPathComponent(uniqueFilename)
                try? FileManager.default.copyItem(at: url, to: copyURL)
                effectiveSourceURL = copyURL
            } else {
                effectiveSourceURL = url
            }

            var entriesForThisURL: [ArchiveEntry] = []

            if entryType == .directory {
                let dirEntry = ArchiveEntry(
                    path: targetPath,
                    type: .directory,
                    uncompressedSize: 0,
                    compressedSize: 0,
                    modifiedAt: Date()
                )
                entriesForThisURL.append(dirEntry)

                if let enumerator = FileManager.default.enumerator(
                    at: effectiveSourceURL,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: []
                ) {
                    while let subItemURL = enumerator.nextObject() as? URL {
                        let relPath = subItemURL.path.replacingOccurrences(of: effectiveSourceURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        guard !relPath.isEmpty else { continue }
                        let subArchivePath = "\(targetPath)/\(relPath)"
                        var subIsDir: ObjCBool = false
                        FileManager.default.fileExists(atPath: subItemURL.path, isDirectory: &subIsDir)
                        let subSz = (try? subItemURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        let subEntry = ArchiveEntry(
                            path: subArchivePath,
                            type: subIsDir.boolValue ? .directory : .file,
                            uncompressedSize: Int64(subSz),
                            compressedSize: Int64(subSz),
                            modifiedAt: Date()
                        )
                        entriesForThisURL.append(subEntry)
                    }
                }
            } else {
                let sz = (try? effectiveSourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let fileEntry = ArchiveEntry(
                    path: targetPath,
                    type: .file,
                    uncompressedSize: Int64(sz),
                    compressedSize: Int64(sz),
                    modifiedAt: Date()
                )
                entriesForThisURL.append(fileEntry)
            }

            let primaryEntry = entriesForThisURL.first ?? ArchiveEntry(path: targetPath, type: entryType)
            undoStack.append(.add(sourceURL: effectiveSourceURL, archivePath: targetPath, primaryEntry: primaryEntry, allCreatedEntries: entriesForThisURL))
            try? entryIndex?.insert(entriesForThisURL)
            allStagedEntries.append(contentsOf: entriesForThisURL)

            selectedEntryID = primaryEntry.id
            selectEntry(primaryEntry)
        }

        redoStack.removeAll()
        hasUnsavedChanges = true
        indexRevision += 1
        try? refreshDisplayedEntries()

        if urls.count == 1, let firstURL = urls.first {
            let origName = firstURL.lastPathComponent
            if existingChildren.contains(where: { $0.name == origName }) {
                statusMessage = "已创建副本「\(allStagedEntries.first?.name ?? origName)」(可按 ⌘Z 撤销)"
            } else {
                statusMessage = "已向当前目录添加「\(origName)」(可按 ⌘Z 撤销)"
            }
        } else {
            statusMessage = "已向当前目录添加 \(urls.count) 个文件 (可按 ⌘Z 撤销)"
        }
    }

    public func undo() {
        guard let lastOp = undoStack.popLast() else { return }
        switch lastOp {
        case let .delete(entry):
            try? entryIndex?.insert([entry])
            try? refreshDisplayedEntries()
            selectedEntryID = entry.id
            statusMessage = "已撤销删除: \(entry.name)"
        case let .rename(originalEntry, newEntry):
            try? entryIndex?.rename(oldCanonicalPath: newEntry.canonicalPath, to: originalEntry)
            try? refreshDisplayedEntries()
            selectedEntryID = originalEntry.id
            statusMessage = "已撤销重命名: \(originalEntry.name)"
        case let .add(_, _, primaryEntry, _):
            try? entryIndex?.remove(canonicalPaths: [primaryEntry.canonicalPath])
            try? refreshDisplayedEntries()
            statusMessage = "已撤销添加: \(primaryEntry.name)"
        }
        redoStack.append(lastOp)
        hasUnsavedChanges = !undoStack.isEmpty
        indexRevision += 1
    }

    public func redo() {
        guard let nextOp = redoStack.popLast() else { return }
        switch nextOp {
        case let .delete(entry):
            try? entryIndex?.remove(canonicalPaths: [entry.canonicalPath])
            try? refreshDisplayedEntries()
            statusMessage = "重做删除: \(entry.name)"
        case let .rename(originalEntry, newEntry):
            try? entryIndex?.rename(oldCanonicalPath: originalEntry.canonicalPath, to: newEntry)
            try? refreshDisplayedEntries()
            selectedEntryID = newEntry.id
            statusMessage = "重做重命名: \(newEntry.name)"
        case let .add(_, _, primaryEntry, allCreatedEntries):
            try? entryIndex?.insert(allCreatedEntries)
            try? refreshDisplayedEntries()
            selectedEntryID = primaryEntry.id
            statusMessage = "重做添加: \(primaryEntry.name)"
        }
        undoStack.append(nextOp)
        hasUnsavedChanges = !undoStack.isEmpty
        indexRevision += 1
    }

    public func savePendingChanges(completionMessage: String? = nil) async {
        guard !isBusy, hasUnsavedChanges, let archiveURL = currentArchiveURL, let desc = currentDescriptor else { return }

        if !isCapsuleMode && PureZipPreferences.shared.deskConfirmLargeBatchOperations && undoStack.count >= 15 {
            let alert = NSAlert()
            alert.messageText = "确认批量提交修改"
            alert.informativeText = "即将对归档「\(archiveURL.lastPathComponent)」写入 \(undoStack.count) 项批量改动，是否确认保存？"
            alert.addButton(withTitle: "保存修改")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
        }

        isBusy = true
        statusMessage = "正在保存修改到 \(archiveURL.lastPathComponent)..."

        var ops: [ChangeSet.Operation] = []
        for op in undoStack {
            switch op {
            case let .delete(entry):
                ops.append(.delete(archivePath: entry.path))
            case let .rename(originalEntry, newEntry):
                ops.append(.rename(from: originalEntry.path, to: newEntry.path))
            case let .add(sourceURL, archivePath, _, _):
                ops.append(.add(sourceURL: sourceURL, archivePath: archivePath))
            }
        }

        do {
            try await broker.apply(
                ChangeSet(operations: ops),
                to: archiveURL,
                profile: CompressionProfile(format: desc.format, level: 6)
            )
            undoStack.removeAll()
            redoStack.removeAll()
            hasUnsavedChanges = false
            await reloadArchiveInPlace()
            statusMessage = completionMessage ?? "已成功保存对归档的修改"
        } catch {
            statusMessage = "保存归档失败: \(error.localizedDescription)"
        }
        isBusy = false
    }

    public func reloadArchiveInPlace() async {
        guard let primaryURL = currentArchiveURL else { return }
        let savedDirectoryPath = currentDirectoryPath
        let savedSelection = selectedEntryID
        do {
            let desc = try await broker.descriptor(for: primaryURL)
            self.currentDescriptor = desc

            entryIndex?.close()
            let newIndex = try EntryIndex()
            self.entryIndex = newIndex

            let stream = try await broker.list(primaryURL, password: currentArchivePassword) { [weak self] comment in
                Task { @MainActor in
                    self?.archiveComment = comment
                }
            }
            for try await batch in stream {
                try newIndex.insert(batch)
            }
            self.currentDirectoryPath = savedDirectoryPath
            try refreshDisplayedEntries()
            self.selectedEntryID = savedSelection
            self.indexRevision += 1
            if desc.format == .dmg {
                let roots = (try? newIndex.children(of: "", limit: 100, includeAuxiliary: true, includeDiskImageBackground: true, includeDMGApplicationsShortcut: true)) ?? []
                var apps = roots.filter { $0.path.lowercased().hasSuffix(".app") || $0.name.lowercased().hasSuffix(".app") }
                if apps.isEmpty, let candidateApps = try? newIndex.findApplicationBundles(limit: 5), !candidateApps.isEmpty {
                    apps = candidateApps
                }
                let hasShortcut = roots.contains { $0.isDMGApplicationsShortcut }
                self.diskImagePresentation = DiskImagePresentation(
                    rootEntries: roots.filter { !$0.isAuxiliary && !$0.isDiskImageBackground },
                    applicationBundleEntries: apps,
                    hasApplicationsShortcut: hasShortcut
                )
            }
        } catch {
            statusMessage = "刷新归档失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Copy, Paste & Duplicate Support (⌘C / ⌘V / ⌘D)

    public func duplicateSelectedEntry() {
        guard let entry = selectedEntryPreview?.entry ?? (selectedEntryID.flatMap { selID in displayedEntries.first(where: { $0.id == selID }) ?? (try? entryIndex?.entry(forID: selID)) }),
              let archiveURL = currentArchiveURL else {
            return
        }

        statusMessage = "正在创建「\(entry.name)」的副本..."
        let broker = self.broker
        let isDirectory = entry.type == .directory
        let descendants = isDirectory ? ((try? entryIndex?.descendants(of: entry.path)) ?? [entry]) : [entry]

        Task {
            do {
                let stagingDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PureZipDuplicatesStaging", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

                if isDirectory {
                    try await broker.extract(archiveURL, entries: descendants, to: stagingDir)
                } else {
                    try await broker.extract(archiveURL, entries: [entry], to: stagingDir)
                }

                var targetURL = stagingDir.appendingPathComponent(entry.path)
                if !FileManager.default.fileExists(atPath: targetURL.path) {
                    let stripped = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let alt = stagingDir.appendingPathComponent(stripped)
                    if FileManager.default.fileExists(atPath: alt.path) {
                        targetURL = alt
                    } else if let enumerator = FileManager.default.enumerator(at: stagingDir, includingPropertiesForKeys: nil) {
                        while let item = enumerator.nextObject() {
                            if let obj = item as? URL, obj.lastPathComponent == entry.name {
                                targetURL = obj
                                break
                            }
                        }
                    }
                }

                if FileManager.default.fileExists(atPath: targetURL.path) {
                    await MainActor.run {
                        self.stageAdd(urls: [targetURL])
                        if self.isCapsuleMode && PureZipPreferences.shared.capsuleWindowAllowEditing {
                            Task {
                                await self.savePendingChanges(completionMessage: "已创建副本并自动保存修改")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "创建副本失败: \(error.localizedDescription)"
                }
            }
        }
    }

    public func copySelectedEntry() {
        guard let entry = selectedEntryPreview?.entry ?? (selectedEntryID.flatMap { selID in displayedEntries.first(where: { $0.id == selID }) ?? (try? entryIndex?.entry(forID: selID)) }),
              let archiveURL = currentArchiveURL else {
            return
        }

        statusMessage = "正在准备复制「\(entry.name)」..."
        let broker = self.broker
        let isDirectory = entry.type == .directory
        let descendants = isDirectory ? ((try? entryIndex?.descendants(of: entry.path)) ?? [entry]) : [entry]

        Task {
            do {
                let stagingDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PureZipClipboardStaging", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

                if isDirectory {
                    try await broker.extract(archiveURL, entries: descendants, to: stagingDir)
                } else {
                    try await broker.extract(archiveURL, entries: [entry], to: stagingDir)
                }

                var targetURL = stagingDir.appendingPathComponent(entry.path)
                if !FileManager.default.fileExists(atPath: targetURL.path) {
                    let stripped = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let alt = stagingDir.appendingPathComponent(stripped)
                    if FileManager.default.fileExists(atPath: alt.path) {
                        targetURL = alt
                    } else if let enumerator = FileManager.default.enumerator(at: stagingDir, includingPropertiesForKeys: nil) {
                        while let item = enumerator.nextObject() {
                            if let obj = item as? URL, obj.lastPathComponent == entry.name {
                                targetURL = obj
                                break
                            }
                        }
                    }
                }

                if FileManager.default.fileExists(atPath: targetURL.path) {
                    await MainActor.run {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([targetURL as NSURL])
                        self.statusMessage = "已复制「\(entry.name)」到剪贴板 (⌘V 可在此目录创建副本或粘贴至其它处)"
                    }
                } else {
                    await MainActor.run {
                        self.statusMessage = "复制失败: 未能生成临时导出文件"
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "复制失败: \(error.localizedDescription)"
                }
            }
        }
    }

    public func pasteFromClipboard() {
        guard !isBusy, currentArchiveURL != nil else { return }
        if isCapsuleMode && !PureZipPreferences.shared.capsuleWindowAllowEditing {
            statusMessage = "当前 Pure Capsule 浮窗处于只读模式（可在设置中开启编辑权限）"
            return
        }
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !items.isEmpty else {
            statusMessage = "剪贴板中没有可粘贴的文件"
            return
        }
        stageAdd(urls: items)
        if isCapsuleMode && PureZipPreferences.shared.capsuleWindowAllowEditing {
            Task {
                await savePendingChanges(completionMessage: "已粘贴并自动保存修改")
            }
        }
    }

    public func promptRename(for entry: ArchiveEntry) {
        guard !isBusy else { return }
        if isCapsuleMode && !PureZipPreferences.shared.capsuleWindowAllowEditing {
            statusMessage = "当前 Pure Capsule 浮窗处于只读模式（可在设置中开启编辑权限）"
            return
        }
        entryBeingRenamed = entry
        isShowingRenameSheet = true
    }

    public func confirmRename(newName: String) {
        guard let entry = entryBeingRenamed else { return }
        isShowingRenameSheet = false
        entryBeingRenamed = nil
        stageRename(entry: entry, newName: newName)
        if isCapsuleMode && PureZipPreferences.shared.capsuleWindowAllowEditing {
            Task {
                await savePendingChanges(completionMessage: "已重命名并自动保存修改")
            }
        }
    }

    public func cancelRename() {
        isShowingRenameSheet = false
        entryBeingRenamed = nil
    }

    public func addFilesToCurrentArchive(_ urls: [URL]) async {
        guard !isBusy else { return }
        if isCapsuleMode && !PureZipPreferences.shared.capsuleWindowAllowEditing {
            statusMessage = "当前 Pure Capsule 浮窗处于只读模式（可在设置中开启编辑权限）"
            return
        }
        stageAdd(urls: urls)
        if isCapsuleMode && PureZipPreferences.shared.capsuleWindowAllowEditing {
            await savePendingChanges(completionMessage: "已添加并自动保存修改")
        }
    }

    public func testCurrentArchiveIntegrity() async {
        guard let archiveURL = currentArchiveURL else { return }
        isBusy = true
        statusMessage = "正在校验 \(archiveURL.lastPathComponent) 的 CRC32 与结构完整性..."
        do {
            try await broker.test(archiveURL)
            statusMessage = "校验通过: \(archiveURL.lastPathComponent) 所有条目 CRC32 完整无损"
        } catch {
            statusMessage = "校验发现异常: \(error.localizedDescription)"
        }
        isBusy = false
    }

    // MARK: - Pure Shelf (Menu Bar Drop Shelf)

    public func addToShelf(_ urls: [URL]) {
        for u in urls.map(\.standardizedFileURL) where !shelfItems.contains(u) {
            shelfItems.append(u)
        }
        statusMessage = "Pure Shelf 当前共 \(shelfItems.count) 项"
    }

    public func removeFromShelf(_ url: URL) {
        shelfItems.removeAll { $0 == url }
    }

    public func clearShelf() {
        shelfItems.removeAll()
    }

    public func compressShelfItems(to destinationURL: URL) async {
        let items = shelfItems
        guard !items.isEmpty else { return }
        let formatStr = PureZipPreferences.shared.pureShelfDefaultFormat
        let targetFormat: ArchiveFormat
        switch formatStr.lowercased() {
        case "7z": targetFormat = .sevenZip
        case "tar.gz", "tar": targetFormat = .tar
        default: targetFormat = .zip
        }

        QuickActionProgressHUD.shared.show(
            title: "正在打包 \(destinationURL.lastPathComponent)",
            symbol: "archivebox"
        )
        isBusy = true
        progressFraction = 0.0
        statusMessage = "正在打包 \(destinationURL.lastPathComponent)..."

        do {
            _ = try await createArchiveDirectly(sources: items, destinationURL: destinationURL, format: targetFormat, level: 6) { [weak self] frac in
                self?.progressFraction = frac
                QuickActionProgressHUD.shared.update(progress: frac)
            }
            QuickActionProgressHUD.shared.finish(message: "已生成 \(destinationURL.lastPathComponent)")
            statusMessage = "打包完成: \(destinationURL.lastPathComponent)"

            if PureZipPreferences.shared.pureShelfAutoClearAfterPackaging {
                await MainActor.run {
                    clearShelf()
                }
            }
        } catch {
            QuickActionProgressHUD.shared.finish(message: "打包失败: \(error.localizedDescription)")
            statusMessage = "打包失败: \(error.localizedDescription)"
        }
        progressFraction = nil
        isBusy = false
    }

    public func quickPackageShelf() {
        guard !shelfItems.isEmpty else { return }
        let panel = NSSavePanel()
        let ext = PureZipPreferences.shared.pureShelfDefaultFormat.lowercased()
        let firstStem: String
        if let first = shelfItems.first {
            let (stem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(first.lastPathComponent)
            firstStem = stem.isEmpty ? "Archive" : stem
        } else {
            firstStem = "Archive"
        }
        panel.nameFieldStringValue = "\(firstStem).\(ext)"
        panel.prompt = "立即打包"
        panel.title = "保存压缩包"
        panel.message = "选择保存位置并命名压缩包"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await compressShelfItems(to: url)
            }
        }
    }

    public func quickExtractShelfArchives() {
        let items = shelfItems
        guard !items.isEmpty else { return }

        let archiveCandidates = items.filter { ArchiveFormatDescriptor.detect(at: $0).format != .unknown }
        let dedupedArchives = ArchiveVolumeFamily.deduplicatedPrimaryArchives(from: archiveCandidates)

        guard !dedupedArchives.isEmpty else {
            statusMessage = "Pure Shelf 中未检测到支持的压缩包"
            return
        }

        // Remove only the extracted archives from shelf, preserving non-archive items
        let extractedSet = Set(archiveCandidates)
        shelfItems.removeAll { extractedSet.contains($0) }

        if dedupedArchives.count == 1, let single = dedupedArchives.first {
            let stem = ArchiveVolumeFamily.extractionFolderStem(for: single)
            let dest = single.deletingLastPathComponent().appendingPathComponent(stem, isDirectory: true)
            Task {
                statusMessage = "正在解压 \(single.lastPathComponent) 到 \(stem)/..."
                do {
                    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                    try await broker.extract(single, entries: [], to: dest, password: nil)
                    statusMessage = "已成功解压到 \(stem)/"
                    NSWorkspace.shared.selectFile(dest.path, inFileViewerRootedAtPath: single.deletingLastPathComponent().path)
                } catch {
                    statusMessage = "解压失败: \(error.localizedDescription)"
                }
            }
        } else {
            BatchExtractionManager.shared.startBatch(urls: dedupedArchives)
            statusMessage = "已启动 \(dedupedArchives.count) 个压缩包的批量解压"
        }
    }

    // MARK: - Built-in Sample Archive Generator for Instant Demo

    public func generateAndOpenDemoArchive() async {
        isBusy = true
        statusMessage = "正在生成包含多级目录、嵌套归档与中文文档的演示归档..."
        do {
            let lease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "demo-builder")
            defer { lease.release() }

            let root = lease.url.appendingPathComponent("PureZip_DemoDesk", isDirectory: true)
            let docsDir = root.appendingPathComponent("文档与说明", isDirectory: true)
            let srcDir = root.appendingPathComponent("Sources/Core", isDirectory: true)
            try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

            try Data("""
            # PureZip 演示归档
            - 双击文件夹可进入多级 SQLite `EntryIndex` 树；
            - 双击 `inner_package.tar.gz` 可直接免手动解压进入**嵌套归档**；
            - 点击右侧预览面板可查看 `SmartCompressionClassifier` 压缩决策与十六进制预览。
            """.utf8).write(to: docsDir.appendingPathComponent("快速上手指南.md"))

            try Data("""
            public struct DemoEngine {
                public static let version = "1.1.0"
            }
            """.utf8).write(to: srcDir.appendingPathComponent("DemoEngine.swift"))

            // Create a nested `.tar.gz` inside the demo desk!
            let innerSource = lease.url.appendingPathComponent("nested_note.txt")
            try Data("这是位于 inner_package.tar.gz 内部的嵌套归档文件！\nNested archive inspection works seamlessly.\n".utf8).write(to: innerSource)
            let nestedTarGz = root.appendingPathComponent("inner_package.tar.gz")
            try await BSDTarEngine().create(
                sources: [innerSource],
                at: nestedTarGz,
                profile: CompressionProfile(format: .tar)
            )

            let demoOutURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PureZip_SampleArchive.zip")
            try? FileManager.default.removeItem(at: demoOutURL)

            await createArchive(sources: [root], destinationURL: demoOutURL, format: .zip, level: 6)
        } catch {
            statusMessage = "生成演示归档失败: \(error.localizedDescription)"
        }
        isBusy = false
    }

    // MARK: - Finder URL Scheme Handling (`purezip://finder-action?...`)

    private var lastHandledURL: URL?
    private var lastHandledTime: Date?

    private func hideAuxiliaryWindowsIfBrowsingInactive() {
        if currentArchiveURL == nil {
            for win in NSApp.windows where win.title == "PureZip" || win.identifier?.rawValue == "main" {
                win.orderOut(nil)
            }
        }
    }

    public func handleIncomingURL(_ url: URL) async {
        if let lastURL = lastHandledURL, let lastTime = lastHandledTime,
           lastURL == url, Date().timeIntervalSince(lastTime) < 0.6 {
            return
        }
        lastHandledURL = url
        lastHandledTime = Date()

        if url.isFileURL {
            await openArchive(at: url)
            return
        }
        guard let ref = FinderActionLaunchURL.reference(from: url) else {
            return
        }
        let store = FinderActionRequestStore()
        guard let req = try? store.consume(ref) else {
            statusMessage = "Finder 扩展请求已过期或无效"
            return
        }

        switch req.action {
        case .browseArchive:
            if let first = req.sources.first {
                let primary = ArchiveVolumeFamily.primaryURL(for: first)
                await openArchive(at: primary)
                openMainWindow()
            }
        case .quickExtractToNamedFolder:
            hideAuxiliaryWindowsIfBrowsingInactive()
            if let first = req.sources.first {
                let primary = ArchiveVolumeFamily.primaryURL(for: first)
                let stem = ArchiveVolumeFamily.extractionFolderStem(for: primary)
                let targetDir = primary.deletingLastPathComponent().appendingPathComponent(stem, isDirectory: true)
                try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                QuickActionProgressHUD.shared.show(title: "正在解压 \(primary.lastPathComponent)", symbol: "folder.badge.plus")
                do {
                    _ = try await extractArchiveDirectly(archiveURL: primary, to: targetDir) { frac in
                        QuickActionProgressHUD.shared.update(progress: frac)
                    }
                    QuickActionProgressHUD.shared.finish(message: "已解压到 \(stem)/")
                } catch {
                    QuickActionProgressHUD.shared.finish(message: "解压失败: \(error.localizedDescription)")
                }
            }
        case .quickExtractHere:
            hideAuxiliaryWindowsIfBrowsingInactive()
            if let first = req.sources.first {
                let primary = ArchiveVolumeFamily.primaryURL(for: first)
                let targetDir = primary.deletingLastPathComponent()
                QuickActionProgressHUD.shared.show(title: "正在解压 \(primary.lastPathComponent)", symbol: "arrow.down.doc")
                do {
                    _ = try await extractArchiveDirectly(archiveURL: primary, to: targetDir) { frac in
                        QuickActionProgressHUD.shared.update(progress: frac)
                    }
                    QuickActionProgressHUD.shared.finish(message: "解压完成")
                } catch {
                    QuickActionProgressHUD.shared.finish(message: "解压失败: \(error.localizedDescription)")
                }
            }
        case .quickExtractTo:
            hideAuxiliaryWindowsIfBrowsingInactive()
            if let first = req.sources.first {
                let primary = ArchiveVolumeFamily.primaryURL(for: first)
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "解压到此处"
                panel.message = "请选择解压文件的目标目录"
                panel.directoryURL = primary.deletingLastPathComponent()
                NSApp.activate(ignoringOtherApps: true)
                let resp = panel.runModal()
                guard resp == .OK, let targetDir = panel.url else { return }

                QuickActionProgressHUD.shared.show(title: "正在解压 \(primary.lastPathComponent)", symbol: "ellipsis.circle")
                do {
                    _ = try await extractArchiveDirectly(archiveURL: primary, to: targetDir) { frac in
                        QuickActionProgressHUD.shared.update(progress: frac)
                    }
                    QuickActionProgressHUD.shared.finish(message: "已解压至目标目录")
                } catch {
                    QuickActionProgressHUD.shared.finish(message: "解压失败: \(error.localizedDescription)")
                }
            }
        case .quickExtractBatchToNamedFolders:
            hideAuxiliaryWindowsIfBrowsingInactive()
            let distinct = ArchiveVolumeFamily.deduplicatedPrimaryArchives(from: req.sources)
            if distinct.count == 1, let first = distinct.first {
                let stem = ArchiveVolumeFamily.extractionFolderStem(for: first)
                let targetDir = first.deletingLastPathComponent().appendingPathComponent(stem, isDirectory: true)
                try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                QuickActionProgressHUD.shared.show(title: "正在解压 \(first.lastPathComponent)", symbol: "folder.badge.plus")
                do {
                    _ = try await extractArchiveDirectly(archiveURL: first, to: targetDir) { frac in
                        QuickActionProgressHUD.shared.update(progress: frac)
                    }
                    QuickActionProgressHUD.shared.finish(message: "已解压到 \(stem)/")
                } catch {
                    QuickActionProgressHUD.shared.finish(message: "解压失败: \(error.localizedDescription)")
                }
            } else if distinct.count > 1 {
                BatchExtractionManager.shared.startBatch(urls: distinct)
                BatchExtractionManager.shared.extractToSubfolder = true
                BatchExtractionManager.shared.runBatchExtraction()
            }
        case .quickExtractBatchHere:
            hideAuxiliaryWindowsIfBrowsingInactive()
            let distinct = ArchiveVolumeFamily.deduplicatedPrimaryArchives(from: req.sources)
            if distinct.count == 1, let first = distinct.first {
                let targetDir = first.deletingLastPathComponent()
                QuickActionProgressHUD.shared.show(title: "正在解压 \(first.lastPathComponent)", symbol: "arrow.down.doc")
                do {
                    _ = try await extractArchiveDirectly(archiveURL: first, to: targetDir) { frac in
                        QuickActionProgressHUD.shared.update(progress: frac)
                    }
                    QuickActionProgressHUD.shared.finish(message: "解压完成")
                } catch {
                    QuickActionProgressHUD.shared.finish(message: "解压失败: \(error.localizedDescription)")
                }
            } else if distinct.count > 1 {
                BatchExtractionManager.shared.startBatch(urls: distinct)
                BatchExtractionManager.shared.extractToSubfolder = false
                BatchExtractionManager.shared.runBatchExtraction()
            }
        case .quickExtractBatchTo:
            hideAuxiliaryWindowsIfBrowsingInactive()
            let distinct = ArchiveVolumeFamily.deduplicatedPrimaryArchives(from: req.sources)
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "批量解压到此处"
            panel.message = "请选择批量解压的目标目录"
            if let first = distinct.first {
                panel.directoryURL = first.deletingLastPathComponent()
            }
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let targetDir = panel.url {
                QuickActionProgressHUD.shared.show(title: "正在批量解压 \(distinct.count) 项...", symbol: "ellipsis.circle")
                for (idx, arch) in distinct.enumerated() {
                    do {
                        _ = try await extractArchiveDirectly(archiveURL: arch, to: targetDir)
                        let frac = Double(idx + 1) / Double(distinct.count)
                        QuickActionProgressHUD.shared.update(progress: frac, subtitle: "已解压 \(idx + 1)/\(distinct.count)")
                    } catch {}
                }
                QuickActionProgressHUD.shared.finish(message: "批量解压完成")
            }
        case .testArchive:
            if let first = req.sources.first {
                let primary = ArchiveVolumeFamily.primaryURL(for: first)
                await openArchive(at: primary)
                openMainWindow()
                await testCurrentArchiveIntegrity()
            }
        case .quickCompressTo:
            hideAuxiliaryWindowsIfBrowsingInactive()
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "压缩到此处"
            panel.message = "请选择压缩包存放目录"
            if let first = req.sources.first {
                panel.directoryURL = first.deletingLastPathComponent()
            }
            NSApp.activate(ignoringOtherApps: true)
            let resp = panel.runModal()
            guard resp == .OK, let targetDir = panel.url else { return }

            let stem = FinderArchiveNaming.suggestedStem(for: req.sources)
            let proposed = targetDir.appendingPathComponent("\(stem).zip")
            let dest = ArchiveOutputFamily.collisionFreeBaseURL(for: proposed)

            QuickActionProgressHUD.shared.show(
                title: "正在压缩 \(dest.lastPathComponent)",
                symbol: "folder.badge.plus"
            )
            do {
                _ = try await createArchiveDirectly(sources: req.sources, destinationURL: dest, format: .zip) { frac in
                    QuickActionProgressHUD.shared.update(progress: frac)
                }
                QuickActionProgressHUD.shared.finish(message: "已生成 \(dest.lastPathComponent)")
            } catch {
                QuickActionProgressHUD.shared.finish(message: "压缩失败: \(error.localizedDescription)")
            }

        case .quickZIP:
            hideAuxiliaryWindowsIfBrowsingInactive()
            if let dest = try? FinderArchiveNaming.availableZIPDestination(for: req.sources) {
                QuickActionProgressHUD.shared.show(
                    title: "正在压缩 \(dest.lastPathComponent)",
                    symbol: "archivebox"
                )
                do {
                    _ = try await createArchiveDirectly(sources: req.sources, destinationURL: dest, format: .zip) { frac in
                        QuickActionProgressHUD.shared.update(progress: frac)
                    }
                    QuickActionProgressHUD.shared.finish(message: "已生成 \(dest.lastPathComponent)")
                } catch {
                    QuickActionProgressHUD.shared.finish(message: "压缩失败: \(error.localizedDescription)")
                }
            }
        case .quick7Z:
            hideAuxiliaryWindowsIfBrowsingInactive()
            if let firstURL = req.sources.first {
                let (stem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(firstURL.lastPathComponent)
                let targetStem = stem.isEmpty ? "Archive" : stem
                let dest = firstURL.deletingLastPathComponent().appendingPathComponent("\(targetStem).7z")
                let freeDest = ArchiveOutputFamily.collisionFreeBaseURL(for: dest)
                QuickActionProgressHUD.shared.show(
                    title: "正在压缩 \(freeDest.lastPathComponent)",
                    symbol: "archivebox"
                )
                do {
                    _ = try await createArchiveDirectly(sources: req.sources, destinationURL: freeDest, format: .sevenZip) { frac in
                        QuickActionProgressHUD.shared.update(progress: frac)
                    }
                    QuickActionProgressHUD.shared.finish(message: "已生成 \(freeDest.lastPathComponent)")
                } catch {
                    QuickActionProgressHUD.shared.finish(message: "压缩失败: \(error.localizedDescription)")
                }
            }
        case .advancedCompression:
            creationSources = req.sources
            openMainWindow()
        case .sendToPureZip:
            addToShelf(req.sources)
        }
    }

    private func addRecentArchive(_ url: URL) {
        recentArchives.removeAll { $0 == url }
        recentArchives.insert(url, at: 0)
        if recentArchives.count > 10 {
            recentArchives.removeLast()
        }
    }
}
