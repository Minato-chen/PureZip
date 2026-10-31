import AppKit
import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

// MARK: - Window Accessor & Configurator

public struct WindowAccessor: NSViewRepresentable {
    public let onWindow: (NSWindow) -> Void

    public init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}

// MARK: - Floppy Disk Save Icon (Toolbar Save Action)

public struct FloppyDiskIcon: View {
    public init() {}

    public var body: some View {
        ZStack {
            // Disk outer body
            RoundedRectangle(cornerRadius: 2)
                .stroke(lineWidth: 1.25)
                .frame(width: 14, height: 14)

            VStack(spacing: 0) {
                // Top metal shutter
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 7, height: 4)

                Spacer()

                // Bottom label / notch
                RoundedRectangle(cornerRadius: 0.8)
                    .stroke(lineWidth: 0.9)
                    .frame(width: 9, height: 4.2)
            }
            .frame(width: 14, height: 13)
            .padding(.vertical, 0.8)
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Native File Entry Row Icon View (System Finder Icons)

public struct ArchiveEntryRowIconView: View {
    public let entry: ArchiveEntry

    public init(entry: ArchiveEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            if entry.type == .directory {
                if entry.name.hasSuffix(".app") {
                    Image(nsImage: NSWorkspace.shared.icon(for: .application))
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                        .resizable()
                        .scaledToFit()
                }
            } else {
                let ext = (entry.name as NSString).pathExtension.lowercased()
                let ut = UTType(filenameExtension: ext) ?? .data
                Image(nsImage: NSWorkspace.shared.icon(for: ut))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Root Adaptive Window View

public struct RootApplicationView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @ObservedObject private var batchManager = BatchExtractionManager.shared
    @ObservedObject private var prefs = PureZipPreferences.shared
    @State private var lastAppliedLayoutModeKey: String = ""

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    private var currentLayoutModeKey: String {
        if session.creationSources != nil {
            return "creation"
        } else if session.currentArchiveURL == nil {
            return "welcome-shelf"
        } else if session.currentDescriptor?.format == .dmg {
            return session.isDMGCapsuleExpanded ? "dmg-expanded" : "dmg-compact"
        } else {
            return session.windowMode == .capsuleFloating ? "capsule" : "desk"
        }
    }

    public var body: some View {
        Group {
            if session.currentArchiveURL == nil {
                // Screen 1: 随航搁板 / 欢迎首页
                PureZipWelcomeView(session: session)
            } else if session.currentDescriptor?.format == .dmg {
                // Screen 2: DMG files ALWAYS use the dedicated Pure Capsule / Canvas view (expanded or compact size)
                CapsuleArchiveWindowView(session: session)
            } else {
                switch session.windowMode {
                case .completeDesk:
                    // Screen 3: 标注大小工作区窗口
                    CompleteDeskView(session: session)
                case .capsuleFloating:
                    // Screen 2: Pure Capsule 胶囊浮窗
                    CapsuleArchiveWindowView(session: session)
                }
            }
        }
        .preferredColorScheme(prefs.preferredColorScheme)
        .sheet(isPresented: Binding(
            get: { session.creationSources != nil },
            set: { if !$0 { session.creationSources = nil } }
        )) {
            if let sources = session.creationSources {
                ArchiveCreationDialogView(sources: sources, session: session)
            }
        }
        .sheet(isPresented: $session.isShowingPasswordPrompt) {
            ArchivePasswordPromptView(session: session)
        }
        .sheet(isPresented: $batchManager.isShowingSheet) {
            BatchExtractionSheetView()
        }
        .quickLookPreview($session.quickLookItemURL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
            handleDroppedProviders(providers)
        }
        .background(
            WindowAccessor { window in
                MainWindowController.shared.attach(window: window, session: session)
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.styleMask.insert([.resizable, .fullSizeContentView])
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                session.updateWindowFloatingLevel()

                let targetSize: NSSize
                let minSize: NSSize

                if session.creationSources != nil {
                    targetSize = NSSize(width: 700, height: 620)
                    minSize = NSSize(width: 640, height: 540)
                } else if session.currentArchiveURL == nil {
                    targetSize = NSSize(width: 440, height: 480)
                    minSize = NSSize(width: 380, height: 380)
                } else if session.currentDescriptor?.format == .dmg {
                    if session.isDMGCapsuleExpanded {
                        targetSize = NSSize(width: 680, height: 500)
                        minSize = NSSize(width: 440, height: 380)
                    } else {
                        targetSize = NSSize(width: 420, height: 440)
                        minSize = NSSize(width: 360, height: 340)
                    }
                } else {
                    switch session.windowMode {
                    case .capsuleFloating:
                        targetSize = NSSize(width: 420, height: 440)
                        minSize = NSSize(width: 360, height: 340)
                    case .completeDesk:
                        targetSize = NSSize(width: 1080, height: 680)
                        minSize = NSSize(width: 860, height: 560)
                    }
                }

                window.minSize = minSize

                let modeKey = currentLayoutModeKey
                let cur = window.frame.size
                if lastAppliedLayoutModeKey != modeKey {
                    DispatchQueue.main.async {
                        self.lastAppliedLayoutModeKey = modeKey
                    }
                    // When switching layout modes, apply the mode's default targetSize (or keep user's larger size if transitioning between shelf & capsule)
                    var frame = window.frame
                    let dy = frame.size.height - targetSize.height
                    frame.origin.y += dy
                    frame.size = targetSize
                    window.setFrame(frame, display: true, animate: true)
                } else if cur.width < minSize.width || cur.height < minSize.height {
                    // Only enforce minimum bounds; never shrink a window that the user manually enlarged!
                    var frame = window.frame
                    let newWidth = max(cur.width, minSize.width)
                    let newHeight = max(cur.height, minSize.height)
                    frame.origin.y -= (newHeight - frame.size.height)
                    frame.size = NSSize(width: newWidth, height: newHeight)
                    window.setFrame(frame, display: true, animate: false)
                }
            }
        )
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        if session.currentArchiveURL != nil && session.isCapsuleMode && !PureZipPreferences.shared.capsuleWindowAllowEditing {
            session.statusMessage = "当前 Pure Capsule 浮窗处于只读模式（可在设置中开启编辑权限）"
            return false
        }
        if session.isBusy {
            return false
        }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    if let url = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<URL?, Error>) in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            continuation.resume(returning: url)
                        }
                    }) {
                        urls.append(url)
                    }
                } else {
                    if let url = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<URL?, Error>) in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            let resolvedURL: URL?
                            if let u = item as? URL {
                                resolvedURL = u
                            } else if let data = item as? Data, let u = URL(dataRepresentation: data, relativeTo: nil) {
                                resolvedURL = u
                            } else if let str = item as? String {
                                resolvedURL = URL(string: str)?.isFileURL == true ? URL(string: str) : URL(fileURLWithPath: str)
                            } else {
                                resolvedURL = nil
                            }
                            continuation.resume(returning: resolvedURL)
                        }
                    }) {
                        urls.append(url)
                    }
                }
            }
            guard !urls.isEmpty else { return }
            await handleDroppedURLs(urls)
        }
        return true
    }

    @MainActor
    private func handleDroppedURLs(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        // Case 1: An archive is ALREADY OPEN in the desk!
        // Dragging ANY file(s) into an open archive means ADDING them to the current archive!
        if session.currentArchiveURL != nil {
            if session.isCapsuleMode && !PureZipPreferences.shared.capsuleWindowAllowEditing {
                session.statusMessage = "当前 Pure Capsule 浮窗处于只读模式（可在设置中开启编辑权限）"
                return
            }
            if session.currentDescriptor?.capabilities.contains(.update) == true {
                await session.addFilesToCurrentArchive(urls)
            } else {
                session.statusMessage = "当前归档 (\(session.currentDescriptor?.displayName ?? "")) 不支持追加文件"
            }
            return
        }

        // Case 2: Welcome screen / No open archive.
        let dedupedArchives = ArchiveVolumeFamily.deduplicatedPrimaryArchives(from: urls.filter { ArchiveFormatDescriptor.detect(at: $0).format != .unknown })
        if !dedupedArchives.isEmpty && dedupedArchives.count == urls.count {
            // All dropped files are archives
            if dedupedArchives.count == 1, let first = dedupedArchives.first {
                await session.openArchive(at: first)
                return
            } else {
                BatchExtractionManager.shared.startBatch(urls: dedupedArchives)
                if let first = dedupedArchives.first {
                    await session.openArchive(at: first)
                }
                return
            }
        } else if dedupedArchives.count == 1 && urls.allSatisfy({ ArchiveVolumeFamily.isSplitArchive(at: $0) }) {
            // Dropped split members of a single split family
            if let first = dedupedArchives.first {
                await session.openArchive(at: first)
                return
            }
        }

        // Case 3: Dropping regular files to Welcome screen stages them in Pure Shelf!
        session.addToShelf(urls)
    }
}

// MARK: - 1. Screen 1: 随航搁板 / 欢迎首页 (Pure Shelf Main)

public struct PureZipWelcomeView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @Environment(\.colorScheme) private var colorScheme

    private var totalShelfSizeString: String {
        var total: Int64 = 0
        for url in session.shelfItems {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let sz = attrs[.size] as? Int64 {
                total += sz
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private func fileSizeString(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sz = attrs[.size] as? Int64 else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
    }

    public var body: some View {
        ZStack {
            // Adaptive background matching Day (clean white) / Night (deep dark)
            RadialGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.14, green: 0.14, blue: 0.16), Color(red: 0.08, green: 0.08, blue: 0.10)]
                    : [Color.white, Color(white: 0.93)],
                center: .center,
                startRadius: 40,
                endRadius: 450
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Custom Header: Logo center, Settings gear right
                HStack(spacing: 8) {
                    // Traffic lights clearance area (left)
                    Color.clear
                        .frame(width: 50, height: 32)

                    Spacer()

                    PureZipBrandBadgeView("Shelf", logoSize: 28)

                    Spacer()

                    HStack(spacing: 8) {
                        // Pin on top toggle button (Pure Shelf Main)
                        Button {
                            session.isPinnedOnTop.toggle()
                        } label: {
                            Image(systemName: session.isPinnedOnTop ? "pin.fill" : "pin")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(session.isPinnedOnTop ? Color(red: 0.88, green: 0.60, blue: 0.05) : .secondary)
                                .frame(width: 30, height: 30)
                                .background(session.isPinnedOnTop ? Color(red: 0.88, green: 0.60, blue: 0.05).opacity(0.18) : (colorScheme == .dark ? Color(white: 0.22) : Color.white))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .help(session.isPinnedOnTop ? "取消窗口置顶" : "置顶当前窗口")

                        Button {
                            session.openSettings(tab: .pureShelf)
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .help("偏好设置")
                    }
                    .frame(minWidth: 50, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)

                if session.shelfItems.isEmpty {
                    // Empty Welcome State
                    Spacer()

                    VStack(spacing: 12) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(colorScheme == .dark ? Color(white: 0.45) : Color(white: 0.60))

                        Text("欢迎！拖入文件以开始")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("拖入压缩包直接浏览，或拖入文件暂存打包")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 24)

                    // Dual Pill Action Buttons
                    HStack(spacing: 18) {
                        Button {
                            promptOpenArchive()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 14))
                                Text("打开压缩包")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 11)
                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                            .cornerRadius(22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)

                        Button {
                            promptCreateArchive()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text("创建压缩包")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.48, blue: 0.98), Color(red: 0.02, green: 0.36, blue: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(22)
                        .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.40), radius: 8, y: 3)
                        .buttonStyle(.plain)
                    }

                    Spacer()
                } else {
                    // Populated Shelf State in Main Window (Matching Bar experience)
                    VStack(spacing: 0) {
                        Spacer().frame(height: 12)

                        // Inner Shelf Card Container
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                                )

                            VStack(spacing: 0) {
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(session.shelfItems, id: \.self) { url in
                                            HStack(spacing: 10) {
                                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                                    .resizable()
                                                    .frame(width: 24, height: 24)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(url.lastPathComponent)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)

                                                    Text(fileSizeString(for: url))
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()

                                                Button {
                                                    session.removeFromShelf(url)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                                            .cornerRadius(10)
                                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 4, y: 1)
                                        }
                                    }
                                    .padding(12)
                                }

                                Divider()

                                // Shelf Bottom Dock
                                HStack {
                                    Text("共 \(session.shelfItems.count) 项 (\(totalShelfSizeString))")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Button("打开压缩包") {
                                        promptOpenArchive()
                                    }
                                    .font(.system(size: 12))
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(colorScheme == .dark ? Color(white: 0.24) : Color.white)
                                    .foregroundStyle(.primary)
                                    .cornerRadius(7)

                                    Button("清空") {
                                        session.clearShelf()
                                    }
                                    .font(.system(size: 12))
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(colorScheme == .dark ? Color(white: 0.24) : Color.white)
                                    .foregroundStyle(.primary)
                                    .cornerRadius(7)

                                    if session.shelfItems.contains(where: { ArchiveFormatDescriptor.detect(at: $0).format != .unknown }) {
                                        Button("快速解压") {
                                            session.quickExtractShelfArchives()
                                        }
                                        .font(.system(size: 12, weight: .semibold))
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(colorScheme == .dark ? Color(white: 0.24) : Color.white)
                                        .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 1.0))
                                        .cornerRadius(7)
                                    }

                                    Button("打包") {
                                        session.quickPackageShelf()
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 5)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(red: 0.05, green: 0.48, blue: 0.98), Color(red: 0.02, green: 0.36, blue: 0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.89))
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
    }

    private func promptOpenArchive() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "选择要浏览或解压的归档文件"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let selectedURLs = panel.urls
            let deduped = ArchiveVolumeFamily.deduplicatedPrimaryArchives(from: selectedURLs)
            if deduped.count == 1, let single = deduped.first {
                Task { await session.openArchive(at: single) }
            } else if deduped.count > 1 {
                Task {
                    BatchExtractionManager.shared.startBatch(urls: deduped)
                    if let first = deduped.first {
                        await session.openArchive(at: first)
                    }
                }
            } else if let first = selectedURLs.first {
                Task { await session.openArchive(at: first) }
            }
        }
    }

    private func promptCreateArchive() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "选择要打包的文件或文件夹"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            session.creationSources = panel.urls
        }
    }
}

// MARK: - DMG 拖拽安装画布视图 (Disk Image Icon Canvas View)

public struct DiskImageIconCanvasView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @State private var isTargeted: Bool = false
    @State private var isInstalling: Bool = false

    private var appEntry: ArchiveEntry? {
        session.diskImagePresentation?.applicationBundleEntries.first
    }

    private var appIcon: NSImage {
        if let custom = session.dmgAppIcon {
            return custom
        }
        let icon = NSWorkspace.shared.icon(for: .applicationBundle)
        icon.size = NSSize(width: 96, height: 96)
        return icon
    }

    private var applicationsIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: "/Applications")
        icon.size = NSSize(width: 96, height: 96)
        return icon
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Instruction header
            HStack {
                Text("拖移应用至“应用程序”文件夹完成安装")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.65))
                Spacer()

                Button {
                    session.openCurrentDMGWithSystemMounter()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 10))
                        Text("使用系统挂载打开")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.22))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("退出 PureZip 预览，使用 macOS 原生磁盘挂载工具打开此 DMG")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Spacer()

            if let app = appEntry {
                // Interactive Drag & Drop Canvas
                HStack(spacing: 36) {
                    // 1. Source App Icon (Draggable)
                    VStack(spacing: 8) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 84, height: 84)
                            .shadow(color: Color.black.opacity(0.40), radius: 10, y: 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .onDrag {
                                ArchiveDragExportManager.shared.itemProvider(for: app, session: session)
                            }

                        Text(app.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("可拖动")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.55))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.20))
                            .cornerRadius(4)
                    }
                    .frame(width: 120)

                    // 2. Center Directional Installation Arrow
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.40, green: 0.55, blue: 1.0), Color(red: 0.65, green: 0.35, blue: 0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color(red: 0.40, green: 0.55, blue: 1.0).opacity(0.4), radius: 8)

                        Text("拖入安装")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(white: 0.60))
                    }

                    // 3. Drop Target: Applications Folder
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isTargeted ? Color.blue.opacity(0.25) : Color(white: 0.16))
                                .frame(width: 96, height: 96)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(isTargeted ? Color.blue : Color.white.opacity(0.20), lineWidth: isTargeted ? 2 : 1)
                                )
                                .scaleEffect(isTargeted ? 1.08 : 1.0)
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)

                            Image(nsImage: applicationsIcon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .shadow(color: isTargeted ? Color.blue.opacity(0.6) : Color.black.opacity(0.35), radius: 10, y: 5)
                        }

                        Text("Applications")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isTargeted ? Color.blue : .white)
                            .lineLimit(1)

                        Text("释放至此")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isTargeted ? Color.blue : Color(white: 0.55))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isTargeted ? Color.blue.opacity(0.2) : Color(white: 0.20))
                            .cornerRadius(4)
                    }
                    .frame(width: 120)
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText, .text, .item, .data, .fileURL], isTargeted: $isTargeted) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            triggerInstall(app)
                        }
                        return true
                    }
                }
                .padding(.vertical, 20)
            } else {
                Text("此磁盘映像中未检测到应用程序包")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.6))
            }

            Spacer()

            // Bottom spacing for dock bar
            Spacer()
                .frame(height: 56)
        }
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
        .background(
            Button("") {
                Task { await session.reloadArchiveInPlace() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private func triggerInstall(_ app: ArchiveEntry) {
        guard !isInstalling else { return }
        isInstalling = true
        Task { @MainActor in
            defer { isInstalling = false }
            do {
                let msg = try await PureActionsRouter.execute(action: .installApplication, for: app, session: session)
                session.statusMessage = msg
            } catch {
                session.statusMessage = "安装失败: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Extract All Split Button (Plan A: 解压到同名文件夹 / 当前文件夹 / 其他位置...)

public struct ExtractAllSplitButton: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @Environment(\.colorScheme) private var colorScheme
    let showsReturnBadge: Bool

    public init(session: ArchiveBrowsingSession, showsReturnBadge: Bool = true) {
        self.session = session
        self.showsReturnBadge = showsReturnBadge
    }

    private var folderStem: String {
        session.suggestedExtractionFolderName
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Main Button: Extract to named subfolder (Default)
            Button {
                Task { await session.extractToNamedSubfolder() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.up")
                        .font(.system(size: 12))
                    Text("全部解压")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if showsReturnBadge {
                        Text("↩")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85))
                            .cornerRadius(3)
                    }
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .help("解压到同名文件夹「\(folderStem)/」")

            // Vertical subtle divider
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.45))
                .frame(width: 1, height: 13)
                .padding(.horizontal, 5)

            // Dropdown Menu
            Menu {
                Button {
                    Task { await session.extractToNamedSubfolder() }
                } label: {
                    Label("解压到同名文件夹「\(folderStem)/」", systemImage: "folder.badge.plus")
                }

                Button {
                    Task { await session.extractToCurrentDirectory() }
                } label: {
                    Label("解压到当前文件夹", systemImage: "arrow.down.doc")
                }

                Divider()

                Button {
                    Task { await session.extractToNamedSubfolder(expandNestedArchives: true) }
                } label: {
                    Label("解压并递归展开内部压缩包「\(folderStem)/」", systemImage: "square.stack.3d.down.right")
                }

                Button {
                    Task { await session.extractToCurrentDirectory(expandNestedArchives: true) }
                } label: {
                    Label("解压到当前文件夹（并展开内部压缩包）", systemImage: "square.stack.3d.up")
                }

                Divider()

                Button {
                    session.extractToCustomDestination()
                } label: {
                    Label("解压到其他位置...", systemImage: "ellipsis.circle")
                }

                Button {
                    session.extractToCustomDestination(expandNestedArchives: true)
                } label: {
                    Label("解压并递归展开到其他位置...", systemImage: "folder.badge.gearshape")
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("选择解压方式")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - 2. Screen 2: Pure Capsule 胶囊浮窗 (Pure Capsule Window)

public struct VisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .sidebar
    public var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    public var state: NSVisualEffectView.State = .active

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

public struct CapsuleArchiveWindowView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @ObservedObject private var prefs = PureZipPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ZStack(alignment: .bottom) {
            if PureZipPreferences.shared.useLiquidGlass {
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
                    .overlay(
                        (colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.40))
                    )
                    .ignoresSafeArea()
            } else {
                (colorScheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(NSColor.windowBackgroundColor))
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Archive File Info Header with integrated Brand Badge (Single unified row)
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: session.currentDescriptor?.format == .dmg ? "externaldrive.fill" : "doc.zipper")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.currentArchiveURL?.lastPathComponent ?? "未命名压缩包")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(session.currentDescriptor?.displayName ?? "ZIP 压缩包") · \(session.totalIndexedCount) 个项目")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Brand badge: larger logo matching height of PureZip + Capsule (2 lines)
                    PureZipBrandBadgeView("Capsule", logoSize: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 28) // Clear clearance below macOS traffic lights
                .padding(.bottom, 10)

                // Breadcrumb bar (Hidden in DMG Canvas mode)
                if !(session.currentDescriptor?.format == .dmg && session.dmgViewMode == .canvas) {
                    HStack(spacing: 8) {
                        // Navigation controls: < ^
                        HStack(spacing: 4) {
                            Button {
                                session.navigateUp()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(!session.canNavigateUp ? Color(NSColor.tertiaryLabelColor) : .primary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .disabled(!session.canNavigateUp)
                            .help("返回上一级目录或外层压缩包")

                            Button {
                                session.navigateUp()
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(!session.canNavigateUp ? Color(NSColor.tertiaryLabelColor) : .primary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .disabled(!session.canNavigateUp)
                            .help("向上返回")
                        }
                        .padding(2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                        .cornerRadius(6)

                        // Path Crumbs Pill with full parent-to-nested archive chain
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    // Parent archive stack crumbs (when browsing inside a nested archive)
                                    ForEach(Array(session.nestedStack.enumerated()), id: \.element.id) { stackIdx, crumb in
                                        Button {
                                            Task { await session.popToNestedArchive(at: stackIdx, directoryPath: "") }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.zipper")
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(.orange)
                                                Text(crumb.displayName)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help("返回外层压缩包「\(crumb.displayName)」根目录")

                                        if !crumb.directoryPath.isEmpty {
                                            let parentSegs = crumb.directoryPath.split(separator: "/").map(String.init)
                                            ForEach(Array(parentSegs.enumerated()), id: \.offset) { pIdx, pSeg in
                                                let pSegPath = parentSegs[0...pIdx].joined(separator: "/")
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))

                                                Button {
                                                    Task { await session.popToNestedArchive(at: stackIdx, directoryPath: pSegPath) }
                                                } label: {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "folder.fill")
                                                            .font(.system(size: 10))
                                                            .foregroundStyle(.secondary)
                                                        Text(pSeg)
                                                            .font(.system(size: 11, weight: .medium))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                                    }

                                    // Current archive root button
                                    Button {
                                        session.navigateToDirectory("")
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: session.currentDescriptor?.format == .dmg ? "externaldrive.fill" : "doc.zipper")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                                            Text(session.currentArchiveURL?.lastPathComponent ?? "归档")
                                                .font(.system(size: 11.5, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .id("capsule-crumb-root")

                                    // Path segments
                                    if !session.currentDirectoryPath.isEmpty {
                                        let segments = session.currentDirectoryPath.split(separator: "/").map(String.init)
                                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                                            let segPath = segments[0...idx].joined(separator: "/")

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(Color(NSColor.tertiaryLabelColor))

                                            Button {
                                                session.navigateToDirectory(segPath)
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "folder.fill")
                                                        .font(.system(size: 10.5))
                                                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                                                    Text(seg)
                                                        .font(.system(size: 11.5, weight: .medium))
                                                        .foregroundStyle(.primary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .id("capsule-crumb-\(idx)")
                                        }
                                    }

                                    Color.clear
                                        .frame(width: 1, height: 1)
                                        .id("capsule-crumb-trailing-anchor")
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4.5)
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .cornerRadius(12)
                            .mask(
                                HStack(spacing: 0) {
                                    if (!session.currentDirectoryPath.isEmpty && session.currentDirectoryPath.contains("/")) || !session.nestedStack.isEmpty {
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.clear, Color.black]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: 16)
                                    }
                                    Rectangle().fill(Color.black)
                                }
                            )
                            .onChange(of: session.currentDirectoryPath) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("capsule-crumb-trailing-anchor", anchor: .trailing)
                                }
                            }
                            .onChange(of: session.nestedStack.count) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("capsule-crumb-trailing-anchor", anchor: .trailing)
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    proxy.scrollTo("capsule-crumb-trailing-anchor", anchor: .trailing)
                                }
                            }
                        }

                        Spacer()

                        if session.currentDescriptor?.format == .dmg {
                            HStack(spacing: 6) {
                                Button {
                                    session.openCurrentDMGWithSystemMounter()
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "externaldrive.badge.plus")
                                            .font(.system(size: 10))
                                        Text("系统挂载")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundStyle(Color.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .help("使用系统原生方式装载此磁盘映像")

                                if session.diskImagePresentation?.applicationBundleEntries.isEmpty == false {
                                    HStack(spacing: 2) {
                                        Button {
                                            session.dmgViewMode = .canvas
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "square.split.2x1")
                                                    .font(.system(size: 10))
                                                Text("画布")
                                                    .font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundStyle(session.dmgViewMode == .canvas ? Color.primary : Color.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(session.dmgViewMode == .canvas ? (colorScheme == .dark ? Color(white: 0.28) : Color(white: 0.88)) : Color.clear)
                                            .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                        .help("拖拽安装画布")

                                        Button {
                                            session.dmgViewMode = .list
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "list.bullet")
                                                    .font(.system(size: 10))
                                                Text("列表")
                                                    .font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundStyle(session.dmgViewMode == .list ? Color.primary : Color.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(session.dmgViewMode == .list ? (colorScheme == .dark ? Color(white: 0.28) : Color(white: 0.88)) : Color.clear)
                                            .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                        .help("文件列表视图")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                if session.currentDescriptor?.format == .dmg && session.diskImagePresentation?.applicationBundleEntries.isEmpty == false && session.dmgViewMode == .canvas {
                    DiskImageIconCanvasView(session: session)
                } else if session.isBusy && session.displayedEntries.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                        Text(session.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 56)
                } else if session.displayedEntries.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        Text("当前目录为空")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 56)
                } else {
                    // List of Entries
                    ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(session.displayedEntries) { entry in
                            let isSelected = session.selectedEntryID == entry.id
                            HStack(spacing: 10) {
                                ArchiveEntryRowIconView(entry: entry)

                                Text(entry.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .lineLimit(1)

                                Spacer()

                                if entry.type != .directory {
                                    Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color(red: 0.88, green: 0.60, blue: 0.05) : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                session.handleDoubleClick(on: entry)
                            }
                            .onTapGesture(count: 1) {
                                session.selectEntry(entry)
                            }
                            .onHover { isHovered in
                                HoverPreviewCoordinator.shared.onRowHover(entry: entry, isHovered: isHovered, session: session)
                            }
                            .onDrag {
                                ArchiveDragExportManager.shared.itemProvider(for: entry, session: session)
                            }
                            .contextMenu {
                                if entry.isNestedArchive {
                                    Button {
                                        Task { await session.openNestedArchive(entry: entry) }
                                    } label: {
                                        Label("进入内部压缩包浏览", systemImage: "arrow.right.doc.on.clipboard")
                                    }

                                    Button {
                                        Task { await session.extractNestedArchiveEntryDirectly(entry) }
                                    } label: {
                                        Label("直接解压内部压缩包到同名文件夹", systemImage: "square.stack.3d.down.right")
                                    }

                                    Divider()
                                }

                                Button {
                                    session.selectEntry(entry)
                                    session.toggleQuickLookForSelected()
                                } label: {
                                    Label("系统快速预览 (空格)", systemImage: "eye")
                                }

                                Button {
                                    session.selectEntry(entry)
                                    session.copySelectedEntry()
                                } label: {
                                    Label("拷贝 (⌘C)", systemImage: "doc.on.doc")
                                }

                                if prefs.capsuleWindowAllowEditing && (session.currentDescriptor?.capabilities.contains(.update) == true) {
                                    Button {
                                        session.selectEntry(entry)
                                        session.duplicateSelectedEntry()
                                    } label: {
                                        Label("创建副本 (⌘D)", systemImage: "plus.square.on.square")
                                    }

                                    Button {
                                        session.pasteFromClipboard()
                                    } label: {
                                        Label("粘贴至此 (⌘V)", systemImage: "doc.on.clipboard")
                                    }

                                    Button {
                                        session.promptRename(for: entry)
                                    } label: {
                                        Label("重命名... (Return)", systemImage: "pencil")
                                    }
                                }

                                Divider()

                                let actions = PureActionsRouter.resolveActions(for: entry)
                                ForEach(actions) { act in
                                    Button {
                                        Task {
                                            let msg = try? await PureActionsRouter.execute(action: act.kind, for: entry, session: session)
                                            session.statusMessage = msg ?? "已执行 \(act.title)"
                                        }
                                    } label: {
                                        Label(act.title, systemImage: act.systemImage)
                                    }
                                }

                                if prefs.capsuleWindowAllowEditing && (session.currentDescriptor?.capabilities.contains(.update) == true) {
                                    Divider()

                                    Button(role: .destructive) {
                                        session.stageDelete(entries: [entry])
                                    } label: {
                                        Label("从归档中删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .id("capsule-entries-\(prefs.capsuleWindowAllowEditing)")
                    .padding(.horizontal, 14)
                    .padding(.bottom, 82) // ample clearance for floating bottom bar
                }
                }
            }

            // Bottom Floating Dock
            HStack(spacing: 8) {
                // Left Capsule: [pin], [expand]
                HStack(spacing: 4) {
                    let useColor = PureZipPreferences.shared.useColorWindowButtons

                    Button {
                        session.isPinnedOnTop.toggle()
                    } label: {
                        Image(systemName: session.isPinnedOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                session.isPinnedOnTop
                                    ? Color(red: 0.88, green: 0.60, blue: 0.05)
                                    : (useColor ? Color(red: 0.95, green: 0.65, blue: 0.15) : Color.primary)
                            )
                            .frame(width: 26, height: 26)
                            .background(
                                session.isPinnedOnTop
                                    ? Color(red: 0.88, green: 0.60, blue: 0.05).opacity(0.18)
                                    : (useColor
                                        ? Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.18)
                                        : (colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90)))
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(session.isPinnedOnTop ? "取消窗口置顶" : "置顶悬浮窗")

                    let isDMG = (session.currentDescriptor?.format == .dmg)

                    Button {
                        session.toggleWindowMode()
                    } label: {
                        Image(systemName: isDMG
                            ? (session.isDMGCapsuleExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            : "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(useColor ? Color(red: 0.20, green: 0.55, blue: 0.95) : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(
                            useColor
                                ? Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.18)
                                : (colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90))
                        )
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isDMG
                        ? (session.isDMGCapsuleExpanded ? "还原迷你窗口尺寸" : "扩大迷你窗口尺寸")
                        : "切换至完整工作区"
                    )
                }
                .padding(3)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 4, y: 2)

                // Pure Actions in non-DMG mode: 快捷动作按钮在钉住关闭右侧齐平空余区域
                if session.currentDescriptor?.format != .dmg,
                   let entry = session.selectedEntryPreview?.entry ?? (session.selectedEntryID.flatMap { selID in session.displayedEntries.first(where: { $0.id == selID }) }) {
                    let actions = PureActionsRouter.resolveActions(for: entry)
                    if let prime = actions.first {
                        Button {
                            Task {
                                let msg = try? await PureActionsRouter.execute(action: prime.kind, for: entry, session: session)
                                session.statusMessage = msg ?? "已完成 \(prime.title)"
                            }
                        } label: {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 4) {
                                    Image(systemName: prime.systemImage.isEmpty ? "bolt.fill" : prime.systemImage)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.yellow)
                                    Text(prime.title)
                                        .font(.system(size: 11, weight: .bold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: prime.systemImage.isEmpty ? "bolt.fill" : prime.systemImage)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.yellow)
                                    Text(compactActionTitle(prime.title))
                                        .font(.system(size: 11, weight: .bold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                Image(systemName: prime.systemImage.isEmpty ? "bolt.fill" : prime.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.yellow)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.05, green: 0.48, blue: 0.98)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.4), radius: 4, y: 1)
                        }
                        .buttonStyle(.plain)
                        .help("智能操作: \(prime.title)")
                        .layoutPriority(1)
                    }
                }

                Spacer()

                // Right Capsule:
                // "但是dmg的时候替换全部解压位置没问题，dmg下预览按钮就不需要了"
                if session.currentDescriptor?.format == .dmg {
                    if let app = session.diskImagePresentation?.applicationBundleEntries.first {
                        Button {
                            Task {
                                let msg = try? await PureActionsRouter.execute(action: .installApplication, for: app, session: session)
                                session.statusMessage = msg ?? "已完成安装"
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.app.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.yellow)
                                Text("安装应用")
                                    .font(.system(size: 12, weight: .bold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Text("↩")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.25))
                                    .cornerRadius(3)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.05, green: 0.48, blue: 0.98)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(18)
                            .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.45), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                } else {
                    // Non-DMG Right Capsule: [eye] 预览 | [tray] 全部解压 [回车] ▾
                    HStack(spacing: 6) {
                        Button {
                            session.toggleQuickLookForSelected()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "eye")
                                    .font(.system(size: 11))
                                Text("预览")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("快速预览 (空格)")
                        .keyboardShortcut(.space, modifiers: [])

                        ExtractAllSplitButton(session: session, showsReturnBadge: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 4, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: (colorScheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(NSColor.windowBackgroundColor)).opacity(0), location: 0),
                        .init(color: (colorScheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(NSColor.windowBackgroundColor)).opacity(0.85), location: 0.4),
                        .init(color: (colorScheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(NSColor.windowBackgroundColor)), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
        }
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
        .sheet(isPresented: $session.isShowingRenameSheet) {
            ArchiveEntryRenameSheet(session: session)
        }
        .background(
            Button("") {
                Task { await session.reloadArchiveInPlace() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                guard prefs.capsuleWindowAllowEditing else { return }
                guard !session.isShowingRenameSheet && !session.isShowingPasswordPrompt else { return }
                session.stageDeleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                guard prefs.capsuleWindowAllowEditing && session.currentDescriptor?.format != .dmg else { return }
                guard !session.isShowingRenameSheet && !session.isShowingPasswordPrompt else { return }
                if let found = session.selectedEntryPreview?.entry ?? (session.selectedEntryID.flatMap { selID in session.displayedEntries.first(where: { $0.id == selID }) }) {
                    session.promptRename(for: found)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private func compactActionTitle(_ title: String) -> String {
        if title.contains("解压") { return "解压" }
        if title.contains("安装") { return "安装" }
        if title.contains("打开") { return "打开" }
        return title
    }

    private func fileIconName(for entry: ArchiveEntry) -> String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if ext == "pdf" { return "doc.richtext" }
        if ["png", "jpg", "jpeg", "webp"].contains(ext) { return "photo" }
        return "doc.text"
    }
}

// MARK: - 3. Screen 3: 标准工作区窗口 (Full Desk Window)

public struct CompleteDeskView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSearching: Bool = false

    public var body: some View {
        HStack(spacing: 0) {
            // Main Content Area
            ZStack(alignment: .bottom) {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Custom Toolbar Area
                    HStack(spacing: 8) {
                        // Archive Icon + Left-aligned Title
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))

                        Text("\(session.currentArchiveURL?.lastPathComponent ?? "未命名归档") /")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        // Segmented View Mode Picker [Icons | List | Columns] using macOS Finder Native Icons
                        HStack(spacing: 2) {
                            ForEach(DeskViewMode.allCases) { mode in
                                Button {
                                    session.viewMode = mode
                                } label: {
                                    if let template = NSImage(named: mode.templateImageName) {
                                        Image(nsImage: template)
                                            .renderingMode(.template)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(session.viewMode == mode ? .white : Color(NSColor.secondaryLabelColor))
                                            .frame(width: 30, height: 26)
                                            .background(session.viewMode == mode ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: mode.systemImage)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(session.viewMode == mode ? .white : Color(NSColor.secondaryLabelColor))
                                            .frame(width: 30, height: 26)
                                            .background(session.viewMode == mode ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("切换为\(mode.rawValue)视图")
                            }
                        }
                        .padding(3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        // Red Delete / Trash Button (Staged Delete)
                        Button {
                            session.stageDeleteSelected()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(session.selectedEntryID != nil ? Color.red : Color.secondary.opacity(0.45))
                                .frame(width: 30, height: 30)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(session.selectedEntryID == nil)
                        .help("从归档中删除选定条目 (可按 ⌘Z 撤销)")

                        // Plus Add Button (Stage Add external files/folders)
                        Button {
                            promptAddFiles()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 30, height: 30)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("添加外部文件或文件夹至当前目录...")

                        // Floppy Disk Save Button (Classic Archive Window)
                        Button {
                            Task {
                                await session.savePendingChanges()
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                FloppyDiskIcon()
                                    .foregroundStyle(session.hasUnsavedChanges ? Color(red: 0.25, green: 0.45, blue: 0.98) : Color(NSColor.secondaryLabelColor).opacity(0.6))
                                    .frame(width: 30, height: 30)
                                    .background(session.hasUnsavedChanges ? Color(red: 0.25, green: 0.45, blue: 0.98).opacity(0.12) : Color(NSColor.controlBackgroundColor))
                                    .clipShape(Circle())

                                if session.hasUnsavedChanges {
                                    Circle()
                                        .fill(Color(red: 0.25, green: 0.45, blue: 0.98))
                                        .frame(width: 6, height: 6)
                                        .offset(x: -2, y: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!session.hasUnsavedChanges || session.isBusy)
                        .help(session.hasUnsavedChanges ? "保存所有修改到压缩包 (⌘S)" : "无未保存的修改")

                        // Search Button / Field
                        if isSearching {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                TextField("搜索条目...", text: $session.searchQuery)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .frame(width: 120)
                                Button {
                                    session.searchQuery = ""
                                    isSearching = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(14)
                        } else {
                            Button {
                                isSearching = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 30, height: 30)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("搜索条目")
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    // Navigation Breadcrumb Bar
                    HStack(spacing: 10) {
                        // Navigation controls: < > ^
                        HStack(spacing: 4) {
                            Button {
                                session.navigateUp()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(!session.canNavigateUp ? Color(NSColor.tertiaryLabelColor) : .primary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(!session.canNavigateUp)
                            .help("返回上一级目录或外层压缩包")

                            Button {} label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(true)

                            Button {
                                session.navigateUp()
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(!session.canNavigateUp ? Color(NSColor.tertiaryLabelColor) : .primary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(!session.canNavigateUp)
                            .help("向上返回")
                        }
                        .padding(2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                        .cornerRadius(6)

                        // Path Crumbs Pill with full parent-to-nested archive chain
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    // Parent archive stack crumbs (when browsing inside a nested archive)
                                    ForEach(Array(session.nestedStack.enumerated()), id: \.element.id) { stackIdx, crumb in
                                        Button {
                                            Task { await session.popToNestedArchive(at: stackIdx, directoryPath: "") }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.zipper")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.orange)
                                                Text(crumb.displayName)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help("返回外层压缩包「\(crumb.displayName)」根目录")

                                        if !crumb.directoryPath.isEmpty {
                                            let parentSegs = crumb.directoryPath.split(separator: "/").map(String.init)
                                            ForEach(Array(parentSegs.enumerated()), id: \.offset) { pIdx, pSeg in
                                                let pSegPath = parentSegs[0...pIdx].joined(separator: "/")
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))

                                                Button {
                                                    Task { await session.popToNestedArchive(at: stackIdx, directoryPath: pSegPath) }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "folder.fill")
                                                            .font(.system(size: 10.5))
                                                            .foregroundStyle(.secondary)
                                                        Text(pSeg)
                                                            .font(.system(size: 11.5, weight: .medium))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                                    }

                                    // Current archive root button
                                    Button {
                                        session.navigateToDirectory("")
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "doc.zipper")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.accentColor)
                                            Text(session.currentArchiveURL?.lastPathComponent ?? "归档")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .id("desk-crumb-root")

                                    // Path segments
                                    if !session.currentDirectoryPath.isEmpty {
                                        let segments = session.currentDirectoryPath.split(separator: "/").map(String.init)
                                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                                            let segPath = segments[0...idx].joined(separator: "/")

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Color(NSColor.tertiaryLabelColor))

                                            Button {
                                                session.navigateToDirectory(segPath)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "folder.fill")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(Color.accentColor)
                                                    Text(seg)
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(.primary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .id("desk-crumb-\(idx)")
                                        }
                                    }

                                    Color.clear
                                        .frame(width: 1, height: 1)
                                        .id("desk-crumb-trailing-anchor")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .cornerRadius(14)
                            .mask(
                                HStack(spacing: 0) {
                                    if (!session.currentDirectoryPath.isEmpty && session.currentDirectoryPath.contains("/")) || !session.nestedStack.isEmpty {
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.clear, Color.black]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: 18)
                                    }
                                    Rectangle().fill(Color.black)
                                }
                            )
                            .onChange(of: session.currentDirectoryPath) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("desk-crumb-trailing-anchor", anchor: .trailing)
                                }
                            }
                            .onChange(of: session.nestedStack.count) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("desk-crumb-trailing-anchor", anchor: .trailing)
                                }
                            }
                            .onAppear {
                                proxy.scrollTo("desk-crumb-trailing-anchor", anchor: .trailing)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                    // Dynamic View Mode Switcher
                    switch session.viewMode {
                    case .columns:
                        EntryColumnBrowserView(session: session)
                            .padding(.bottom, 60)
                    case .icons:
                        EntryIconGridView(session: session)
                            .padding(.bottom, 60)
                    case .list:
                        // Table Column Headers: 名称 | 大小 | 修改时间
                        HStack {
                            Text("名称")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("大小")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Text("修改时间")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 180, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)

                        Divider()

                        // Table Rows
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(session.displayedEntries) { entry in
                                    let isSelected = session.selectedEntryID == entry.id
                                    HStack {
                                        HStack(spacing: 10) {
                                            ArchiveEntryRowIconView(entry: entry)

                                            Text(entry.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(isSelected ? .white : .primary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Text(entry.type == .directory ? "--" : ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(isSelected ? .white : .secondary)
                                            .frame(width: 100, alignment: .leading)

                                        Text(entryDateFormatted(entry: entry))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(isSelected ? .white : .secondary)
                                            .frame(width: 180, alignment: .leading)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color.accentColor : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                    .onHover { isHovered in
                                        HoverPreviewCoordinator.shared.onRowHover(entry: entry, isHovered: isHovered, session: session)
                                    }
                                    .onDrag {
                                        ArchiveDragExportManager.shared.itemProvider(for: entry, session: session)
                                    }
                                    .onTapGesture(count: 2) {
                                        session.handleDoubleClick(on: entry)
                                    }
                                    .onTapGesture(count: 1) {
                                        session.selectEntry(entry)
                                    }
                                    .contextMenu {
                                        if entry.isNestedArchive {
                                            Button {
                                                Task { await session.openNestedArchive(entry: entry) }
                                            } label: {
                                                Label("进入内部压缩包浏览", systemImage: "arrow.right.doc.on.clipboard")
                                            }

                                            Button {
                                                Task { await session.extractNestedArchiveEntryDirectly(entry) }
                                            } label: {
                                                Label("直接解压内部压缩包到同名文件夹", systemImage: "square.stack.3d.down.right")
                                            }

                                            Divider()
                                        }

                                        Button {
                                            session.selectEntry(entry)
                                            session.toggleQuickLookForSelected()
                                        } label: {
                                            Label("系统快速预览 (空格)", systemImage: "eye")
                                        }

                                        Button {
                                            session.selectEntry(entry)
                                            session.copySelectedEntry()
                                        } label: {
                                            Label("拷贝 (⌘C)", systemImage: "doc.on.doc")
                                        }

                                        Button {
                                            session.selectEntry(entry)
                                            session.duplicateSelectedEntry()
                                        } label: {
                                            Label("创建副本 (⌘D)", systemImage: "plus.square.on.square")
                                        }

                                        Button {
                                            session.pasteFromClipboard()
                                        } label: {
                                            Label("粘贴至此 (⌘V)", systemImage: "doc.on.clipboard")
                                        }

                                        Button {
                                            session.promptRename(for: entry)
                                        } label: {
                                            Label("重命名... (Return)", systemImage: "pencil")
                                        }

                                        Divider()

                                        let actions = PureActionsRouter.resolveActions(for: entry)
                                        ForEach(actions) { act in
                                            Button {
                                                Task {
                                                    let msg = try? await PureActionsRouter.execute(action: act.kind, for: entry, session: session)
                                                    session.statusMessage = msg ?? "已执行 \(act.title)"
                                                }
                                            } label: {
                                                Label(act.title, systemImage: act.systemImage)
                                            }
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            session.stageDelete(entries: [entry])
                                        } label: {
                                            Label("从归档中删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 4)
                            .padding(.bottom, 80) // Dock breathing room
                        }
                    }
                }

                // Bottom Floating Control Dock
                HStack(spacing: 12) {
                    // Left Capsule: [Pin Switch] [Capsule Switch]
                    HStack(spacing: 8) {
                        Button {
                            session.isPinnedOnTop.toggle()
                        } label: {
                            Image(systemName: session.isPinnedOnTop ? "pin.fill" : "pin")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(session.isPinnedOnTop ? Color(red: 0.88, green: 0.60, blue: 0.05) : Color.primary)
                                .frame(width: 26, height: 26)
                                .background(session.isPinnedOnTop ? Color(red: 0.88, green: 0.60, blue: 0.05).opacity(0.18) : (colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90)))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(session.isPinnedOnTop ? "取消窗口置顶" : "置顶当前窗口")

                        Button {
                            session.toggleWindowMode()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 26, height: 26)
                                .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("收起为 Pure Capsule 胶囊浮窗")
                    }
                    .padding(3)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 4, y: 2)

                    // Pure Actions button in non-DMG mode: 快捷动作按钮在钉住关闭右侧齐平空余区域
                    if session.currentDescriptor?.format != .dmg,
                       let entry = session.selectedEntryPreview?.entry ?? (session.selectedEntryID.flatMap { selID in session.displayedEntries.first(where: { $0.id == selID }) }) {
                        let actions = PureActionsRouter.resolveActions(for: entry)
                        if let prime = actions.first {
                            Button {
                                Task {
                                    let msg = try? await PureActionsRouter.execute(action: prime.kind, for: entry, session: session)
                                    session.statusMessage = msg ?? "已完成"
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: prime.systemImage.isEmpty ? "bolt.fill" : prime.systemImage)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.yellow)
                                    Text(prime.title)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.05, green: 0.48, blue: 0.98)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.4), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    // Right Capsule:
                    // If DMG: "dmg的时候替换全部解压位置没问题，dmg下预览按钮就不需要了"
                    if session.currentDescriptor?.format == .dmg {
                        if let app = session.diskImagePresentation?.applicationBundleEntries.first {
                            Button {
                                Task {
                                    let msg = try? await PureActionsRouter.execute(action: .installApplication, for: app, session: session)
                                    session.statusMessage = msg ?? "已完成安装"
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.app.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.yellow)
                                    Text("安装应用")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("↩")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.25))
                                        .cornerRadius(3)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.05, green: 0.48, blue: 0.98)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(18)
                                .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.45), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.return, modifiers: [])
                        }
                    } else {
                        // Non-DMG Right Capsule: [eye] 预览 [空格] | [tray] 全部解压 [回车] ▾
                        HStack(spacing: 8) {
                            Button {
                                session.toggleQuickLookForSelected()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "eye")
                                        .font(.system(size: 12))
                                    Text("预览")
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Text("空格")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85))
                                        .cornerRadius(3)
                                }
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .help("快速预览 (空格)")
                            .keyboardShortcut(.space, modifiers: [])

                            ExtractAllSplitButton(session: session, showsReturnBadge: true)
                        }
                        .padding(3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 4, y: 2)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }

            // Unified right Inspector across all views (Icons, List, Columns)
            Divider()
            inspectorPane
                .frame(width: 290)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .sheet(isPresented: $session.isShowingRenameSheet) {
            ArchiveEntryRenameSheet(session: session)
        }
        .background(
            Button("") {
                Task { await session.reloadArchiveInPlace() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                session.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                session.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                if session.hasUnsavedChanges {
                    Task { await session.savePendingChanges() }
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                guard !session.isShowingRenameSheet && !session.isShowingPasswordPrompt else { return }
                if let found = session.selectedEntryPreview?.entry ?? (session.selectedEntryID.flatMap { selID in session.displayedEntries.first(where: { $0.id == selID }) }) {
                    session.promptRename(for: found)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                session.copySelectedEntry()
            }
            .keyboardShortcut("c", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                session.duplicateSelectedEntry()
            }
            .keyboardShortcut("d", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                session.pasteFromClipboard()
            }
            .keyboardShortcut("v", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                guard !session.isShowingRenameSheet && !session.isShowingPasswordPrompt else { return }
                session.stageDeleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private var pureActionLabel: String {
        if let entry = session.selectedEntryPreview?.entry ?? (session.selectedEntryID.flatMap { selID in session.displayedEntries.first(where: { $0.id == selID }) }) {
            let actions = PureActionsRouter.resolveActions(for: entry)
            return actions.first?.title ?? "打开文件"
        }
        return "打开文件"
    }

    private func displaySize(for entry: ArchiveEntry) -> String {
        if entry.type == .directory {
            if let descendants = try? session.entryIndex?.descendants(of: entry.path) {
                let size = descendants.filter { $0.type != .directory }.reduce(0) { $0 + $1.uncompressedSize }
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file)
    }

    private func compactActionTitle(_ title: String) -> String {
        if title.contains("解压") { return "解压" }
        if title.contains("安装") { return "安装" }
        if title.contains("打开") { return "打开" }
        return title
    }

    private func fileIconName(for entry: ArchiveEntry) -> String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if ext == "pdf" { return "doc.richtext" }
        if ["png", "jpg", "jpeg", "webp"].contains(ext) { return "photo" }
        return "doc.text"
    }

    private func entryDateFormatted(entry: ArchiveEntry) -> String {
        guard let date = entry.modifiedAt else { return "--" }
        return PureZipDateFormatter.entryListFormatter.string(from: date)
    }

    private func promptAddFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加至归档"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            Task { await session.addFilesToCurrentArchive(panel.urls) }
        }
    }

    // MARK: Right Inspector

    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("项目详情")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 24)
                .padding(.horizontal, 20)

            if let preview = session.selectedEntryPreview {
                if let nestedSummary = preview.nestedArchiveSummary {
                    // Nested Archive Live Inspection Card in Inspector
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("内部压缩包透视")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("\(nestedSummary.formatDisplayName) · 共 \(nestedSummary.totalEntryCount) 项 · \(ByteCountFormatter.string(fromByteCount: nestedSummary.totalUncompressedBytes, countStyle: .file))")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        Divider()

                        if nestedSummary.topEntries.isEmpty {
                            Text("该嵌套压缩包为空或需要密码访问")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(nestedSummary.topEntries) { item in
                                        HStack(spacing: 6) {
                                            Image(systemName: fileSystemIconName(for: item))
                                                .font(.system(size: 11))
                                                .foregroundStyle(fileSystemIconColor(for: item))
                                                .frame(width: 14)
                                            Text(item.path)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            if item.type != .directory {
                                                Text(ByteCountFormatter.string(fromByteCount: item.uncompressedSize, countStyle: .file))
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    if nestedSummary.totalEntryCount > nestedSummary.topEntries.count {
                                        Text("... 其余 \(nestedSummary.totalEntryCount - nestedSummary.topEntries.count) 个项目")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 2)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                Task { await session.openNestedArchive(entry: preview.entry) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 11))
                                    Text("进入内部浏览")
                                        .font(.system(size: 11.5, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .cornerRadius(7)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task { await session.extractNestedArchiveEntryDirectly(preview.entry) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "tray.and.arrow.up")
                                        .font(.system(size: 11))
                                    Text("直接解压")
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(7)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("直接将此内部压缩包解压到外部同名文件夹")
                        }
                    }
                    .padding(12)
                    .frame(height: 265)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    )
                    .padding(.horizontal, 20)
                } else if let mediaURL = preview.mediaFileURL, let vData = preview.videoMetadata {
                    // Video Interactive Player in Inspector
                    InspectorVideoPlayerView(url: mediaURL, metadata: vData, entryName: preview.entry.name)
                        .id(mediaURL)
                        .padding(.horizontal, 20)
                } else if let mediaURL = preview.mediaFileURL, let aData = preview.audioMetadata {
                    // Audio Interactive Waveform Player in Inspector
                    InspectorAudioPlayerView(url: mediaURL, metadata: aData, entryName: preview.entry.name)
                        .id(mediaURL)
                } else {
                    // Large Card with Rendered Thumbnail Preview (Images, 3D, PDF, Text, Folders)
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                        if let img = preview.image {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                                .cornerRadius(8)
                        } else if let modelURL = preview.model3DURL {
                            Model3DPreviewView(fileURL: modelURL)
                                .cornerRadius(8)
                                .padding(4)
                        } else if preview.entry.type == .directory {
                            Image(nsImage: nativeFinderIcon(for: preview.entry, size: 88))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 88, height: 88)
                        } else if let text = preview.textContent, !text.isEmpty {
                            MarkdownTextPreviewView(text: text)
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            VStack(spacing: 8) {
                                Image(nsImage: nativeFinderIcon(for: preview.entry, size: 72))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 72)
                                Text(preview.entry.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .frame(height: 250)
                    .padding(.horizontal, 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        session.toggleQuickLookForSelected()
                    }
                    .help("点击打开系统快速预览 (QuickLook)")
                }

                // Entry Info Details Below Card
                VStack(alignment: .leading, spacing: 6) {
                    if preview.audioMetadata == nil {
                        Text(preview.entry.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }

                    Text(systemKind(for: preview.entry))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("原始大小")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(displaySize(for: preview.entry))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                        }

                        if let vData = preview.videoMetadata {
                            HStack {
                                Text("视频规格")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(vData.resolutionFormatted) · \(vData.codecName)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }

                        if let aData = preview.audioMetadata {
                            HStack {
                                Text("音频规格")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(aData.specBadge)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }

                        HStack {
                            Text("加密")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(preview.entry.encrypted ? "是" : "否")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        HStack {
                            Text("修改日期")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entryDateFormatted(entry: preview.entry))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 20)
            } else if session.isLoadingEntryPreview {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在快速准备预览...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    Text("选中条目以查看项目详情")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()
        }
    }

    private func typeDescription(for entry: ArchiveEntry) -> String {
        if entry.type == .directory { return "文件夹" }
        let ext = (entry.name as NSString).pathExtension.uppercased()
        if ext.isEmpty { return "文件" }
        return "\(ext) 文档"
    }
}

// MARK: - Menu Bar Shelf View ("Pure Shelf Bar")

public struct MenuBarShelfView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @ObservedObject var prefs = PureZipPreferences.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isTargeted: Bool = false
    @State private var isPinned: Bool = false

    public init(session: ArchiveBrowsingSession) {
        self.session = session
        _isPinned = State(initialValue: PureZipPreferences.shared.pureShelfKeepWindowPinned)
    }

    private var totalShelfSizeString: String {
        var total: Int64 = 0
        for url in session.shelfItems {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let sz = attrs[.size] as? Int64 {
                total += sz
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Header (Matching Pure Shelf Design)
            HStack(spacing: 6) {
                // Left: Logo + App Name + Capsule Badge (Clicking opens main window)
                Button {
                    session.openMainWindow()
                } label: {
                    PureZipBrandBadgeView("Shelf", logoSize: 26)
                }
                .buttonStyle(.plain)
                .help("点击打开主窗口")

                Spacer(minLength: 8)

                // Right 4 Circular Action Buttons (Uniform 26x26 styling)
                HStack(spacing: 5) {
                    // 1. Open Main Window Button (打开主窗口)
                    Button {
                        session.openMainWindow()
                    } label: {
                        Image(systemName: "macwindow")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("打开主窗口")

                    // 2. Pin Button (固定)
                    Button {
                        isPinned.toggle()
                        prefs.pureShelfKeepWindowPinned = isPinned
                        PureZipStatusItemController.shared?.setPinned(isPinned)
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isPinned ? Color(red: 0.88, green: 0.60, blue: 0.05) : .secondary)
                            .frame(width: 26, height: 26)
                            .background(isPinned ? Color(red: 0.88, green: 0.60, blue: 0.05).opacity(0.18) : (colorScheme == .dark ? Color(white: 0.22) : Color.white))
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "取消浮窗固定" : "固定 Pure Shelf 浮窗")

                    // 3. Settings Button (偏好设置)
                    Button {
                        session.openSettings(tab: .pureShelf)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Pure Shelf 偏好设置...")

                    // 4. Close Button (关闭浮窗 - 只关闭浮窗，绝不关闭主程序)
                    Button {
                        PureZipStatusItemController.shared?.closePopover()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("关闭浮窗")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // MARK: - Inner Shelf Card Container
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isTargeted ? Color(red: 0.05, green: 0.48, blue: 0.98) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                                lineWidth: isTargeted ? 2.5 : 1
                            )
                    )

                if session.shelfItems.isEmpty {
                    // Empty State: Subtle Watermark + Large Tray Icon + Drop Area
                    VStack(spacing: 8) {
                        Spacer()

                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 54, weight: .ultraLight))
                            .foregroundStyle(isTargeted ? Color(red: 0.05, green: 0.48, blue: 0.98) : (colorScheme == .dark ? Color(white: 0.40) : Color(white: 0.62)))

                        if isTargeted {
                            Text("松手添加至 Pure Shelf")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                        } else {
                            Text("可从访达拖入文件，或点击添加")
                                .font(.system(size: 11))
                                .foregroundStyle(colorScheme == .dark ? Color(white: 0.65) : Color(white: 0.55))
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        promptAddFiles()
                    }
                } else {
                    // Populated State: Item List + Bottom Actions
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(session.shelfItems, id: \.self) { url in
                                    HStack(spacing: 8) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                            .resizable()
                                            .frame(width: 20, height: 20)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            Text(fileSizeString(for: url))
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button {
                                            session.removeFromShelf(url)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.04), radius: 3, y: 1)
                                }
                            }
                            .padding(10)
                        }

                        Divider()

                        HStack {
                            Text("共 \(session.shelfItems.count) 项 (\(totalShelfSizeString))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("清空") {
                                session.clearShelf()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorScheme == .dark ? Color(white: 0.24) : Color.white)
                            .foregroundStyle(.primary)
                            .cornerRadius(6)

                            if session.shelfItems.contains(where: { ArchiveFormatDescriptor.detect(at: $0).format != .unknown }) {
                                Button("快速解压") {
                                    session.quickExtractShelfArchives()
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(colorScheme == .dark ? Color(white: 0.24) : Color.white)
                                .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 1.0))
                                .cornerRadius(6)
                            }

                            Button("打包") {
                                session.quickPackageShelf()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.05, green: 0.48, blue: 0.98), Color(red: 0.02, green: 0.36, blue: 0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.89))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(height: 275)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
        .frame(width: 350, height: 350)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(white: 0.98))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.12), radius: 12, x: 0, y: 5)
        .contextMenu {
            Button("偏好设置...") {
                session.openSettings(tab: .pureShelf)
            }
            if !session.shelfItems.isEmpty {
                Divider()
                Button("清空 Pure Shelf") {
                    session.clearShelf()
                }
            }
            Divider()
            Button("退出 PureZip") {
                NSApp.terminate(nil)
            }
        }
        .preferredColorScheme(prefs.preferredColorScheme)
        .onAppear {
            isPinned = prefs.pureShelfKeepWindowPinned
            PureZipStatusItemController.shared?.applyPinningState()
        }
    }

    private func fileSizeString(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sz = attrs[.size] as? Int64 else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
    }

    private func promptAddFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加至 Pure Shelf"
        if panel.runModal() == .OK {
            session.addToShelf(panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            if p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async { urls.append(url) }
                    }
                    group.leave()
                }
            } else {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let res: URL?
                    if let u = item as? URL { res = u }
                    else if let d = item as? Data { res = URL(dataRepresentation: d, relativeTo: nil) }
                    else if let s = item as? String { res = URL(string: s)?.isFileURL == true ? URL(string: s) : URL(fileURLWithPath: s) }
                    else { res = nil }
                    if let res {
                        DispatchQueue.main.async { urls.append(res) }
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty {
                session.addToShelf(urls)
            }
        }
        return true
    }
}
