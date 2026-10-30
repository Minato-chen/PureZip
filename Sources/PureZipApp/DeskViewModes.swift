import AppKit
import SwiftUI
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ArchiveCore
import ArchiveEngines

public enum DeskViewMode: String, CaseIterable, Identifiable, Sendable {
    case icons   = "图标"
    case list    = "列表"
    case columns = "分栏"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .icons:   return "square.grid.2x2"
        case .list:    return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        }
    }

    /// Native macOS Finder toolbar template image name
    public var templateImageName: String {
        switch self {
        case .icons:   return NSImage.iconViewTemplateName
        case .list:    return NSImage.listViewTemplateName
        case .columns: return NSImage.columnViewTemplateName
        }
    }
}

// MARK: - 1. Native macOS Icons Grid View (图标网格视图 - 支持真实缩略图与系统原生图标)

public struct EntryIconGridView: View {
    @ObservedObject var session: ArchiveBrowsingSession

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 128), spacing: 16)
    ]

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(session.displayedEntries) { entry in
                    let isSelected = session.selectedEntryID == entry.id
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            EntryThumbnailAsyncView(entry: entry, session: session, size: 64)
                                .frame(width: 64, height: 64)

                            if entry.encrypted {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                    .offset(x: 4, y: -2)
                            }
                        }

                        Text(entry.name)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .cornerRadius(4)

                        if entry.type != .directory {
                            Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(width: 108, height: 122)
                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    .cornerRadius(8)
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

                        Button("解压此项") {
                            if let archiveURL = session.currentArchiveURL {
                                Task {
                                    await session.extractArchive(entries: [entry], to: archiveURL.deletingLastPathComponent())
                                }
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
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Native macOS Finder Thumbnail & Icon Generator
public struct EntryThumbnailAsyncView: View {
    let entry: ArchiveEntry
    @ObservedObject var session: ArchiveBrowsingSession
    let size: CGFloat

    @State private var thumbnailImage: NSImage?

    public init(entry: ArchiveEntry, session: ArchiveBrowsingSession, size: CGFloat = 64) {
        self.entry = entry
        self.session = session
        self.size = size
    }

    private var ext: String {
        (entry.name as NSString).pathExtension.lowercased()
    }

    private var isThumbnailCandidate: Bool {
        entry.type != .directory &&
        entry.uncompressedSize <= 25 * 1024 * 1024 &&
        ["png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "tiff", "ico", "pdf", "docx", "xlsx", "pptx", "pages", "numbers", "key"].contains(ext)
    }

    public var body: some View {
        Group {
            if let thumb = thumbnailImage {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(4)
                    .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1.5)
            } else {
                Image(nsImage: nativeFinderIcon(for: entry, size: size))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .task(id: entry.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard isThumbnailCandidate else { return }

        let cacheKey = "\(session.currentArchiveURL?.path ?? ""):\(entry.path)"
        if let cached = PreviewArtifactCache.shared.image(for: cacheKey) {
            self.thumbnailImage = cached
            return
        }
        if let pages = PreviewArtifactCache.shared.pdfPages(for: cacheKey), let first = pages.first {
            self.thumbnailImage = first
            return
        }

        guard let archiveURL = session.currentArchiveURL else { return }

        do {
            let lease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "thumb")
            defer { lease.release() }
            try await session.broker.extract(archiveURL, entries: [entry], to: lease.url)

            var fileURL = lease.url.appendingPathComponent(entry.path)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let stripped = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let altURL = lease.url.appendingPathComponent(stripped)
                if FileManager.default.fileExists(atPath: altURL.path) {
                    fileURL = altURL
                } else if let enumerator = FileManager.default.enumerator(at: lease.url, includingPropertiesForKeys: nil) {
                    while let item = enumerator.nextObject() {
                        if let itemURL = item as? URL, itemURL.lastPathComponent == entry.name {
                            fileURL = itemURL
                            break
                        }
                    }
                }
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

            if ["png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "tiff", "ico"].contains(ext) {
                if let img = NSImage(contentsOf: fileURL) {
                    PreviewArtifactCache.shared.setImage(img, for: cacheKey)
                    self.thumbnailImage = img
                }
            } else if ext == "pdf", let pdfDoc = PDFDocument(url: fileURL), let page = pdfDoc.page(at: 0) {
                let thumb = renderHighResolutionPDFPage(page, targetWidth: max(256, size * 4))
                PreviewArtifactCache.shared.setImage(thumb, for: cacheKey)
                self.thumbnailImage = thumb
            } else if ["docx", "xlsx", "pptx", "pages", "numbers", "key"].contains(ext) {
                let req = QLThumbnailGenerator.Request(
                    fileAt: fileURL,
                    size: CGSize(width: size * 2, height: size * 2),
                    scale: NSScreen.main?.backingScaleFactor ?? 2.0,
                    representationTypes: .thumbnail
                )
                let (rep, _) = await withCheckedContinuation { continuation in
                    QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, err in
                        continuation.resume(returning: (rep, err))
                    }
                }
                if let qlImg = rep?.nsImage {
                    PreviewArtifactCache.shared.setImage(qlImg, for: cacheKey)
                    self.thumbnailImage = qlImg
                }
            }
        } catch {}
    }
}

// MARK: - 2. Native macOS Miller Columns View (分栏视图 + 项目详情)

public struct EntryColumnBrowserView: View {
    @ObservedObject var session: ArchiveBrowsingSession

    public struct ColumnNode: Identifiable {
        public let id = UUID()
        public let path: String
        public var entries: [ArchiveEntry]
        public var selectedName: String?
    }

    @State private var columnNodes: [ColumnNode] = []
    @State private var activeEntry: ArchiveEntry? = nil
    @State private var activeFolderSize: Int64? = nil

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    public var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(Array(columnNodes.enumerated()), id: \.element.id) { index, node in
                            ColumnListView(
                                node: node,
                                columnIndex: index,
                                onSelect: { entry in
                                    handleSelection(entry: entry, at: index)
                                },
                                onDoubleClick: { entry in
                                    handleDoubleClick(entry: entry, at: index)
                                },
                                session: session
                            )
                            .frame(width: 220)
                            .id(node.id)

                            Divider()
                        }
                    }
                    .frame(minWidth: geo.size.width, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .onChange(of: columnNodes.count) {
                    scrollToAppropriateColumn(proxy: proxy, viewportWidth: geo.size.width)
                }
                .onChange(of: session.currentDirectoryPath) { _, newPath in
                    syncColumnsToCurrentDirectory(path: newPath)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToAppropriateColumn(proxy: proxy, viewportWidth: geo.size.width)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            initializeColumns()
        }
        .onChange(of: session.currentArchiveURL) {
            initializeColumns()
        }
        .onChange(of: session.indexRevision) {
            initializeColumns()
        }
    }

    private func scrollToAppropriateColumn(proxy: ScrollViewProxy, viewportWidth: CGFloat) {
        let totalWidth = CGFloat(columnNodes.count) * 220
        if totalWidth > viewportWidth {
            if let lastID = columnNodes.last?.id {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(lastID, anchor: .trailing)
                }
            }
        } else {
            if let firstID = columnNodes.first?.id {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(firstID, anchor: .leading)
                }
            }
        }
    }

    private func syncColumnsToCurrentDirectory(path: String) {
        guard let index = session.entryIndex else { return }

        // Canonical empty path represents the archive root
        if path.isEmpty {
            let roots = (try? index.children(of: "", limit: 1000, includeAuxiliary: session.includeAuxiliary)) ?? []
            self.columnNodes = [
                ColumnNode(path: "", entries: roots, selectedName: nil)
            ]
            if let first = roots.first {
                self.activeEntry = first
                session.selectEntry(first)
                updateActiveDetails(for: first)
            } else {
                self.activeEntry = nil
                self.activeFolderSize = nil
            }
            return
        }

        let currentLeafPath = columnNodes.last?.path ?? ""
        if currentLeafPath == path { return }

        let roots = (try? index.children(of: "", limit: 1000, includeAuxiliary: session.includeAuxiliary)) ?? []
        var nodes: [ColumnNode] = [
            ColumnNode(path: "", entries: roots, selectedName: nil)
        ]

        let parts = path.split(separator: "/").map(String.init)
        var currentPath = ""
        for (idx, part) in parts.enumerated() {
            if idx < nodes.count {
                nodes[idx].selectedName = part
            }
            currentPath = currentPath.isEmpty ? part : "\(currentPath)/\(part)"
            let subs = (try? index.children(of: currentPath, limit: 1000, includeAuxiliary: session.includeAuxiliary)) ?? []
            nodes.append(ColumnNode(path: currentPath, entries: subs, selectedName: nil))
        }

        self.columnNodes = nodes
        if let lastSelected = nodes.last?.entries.first {
            self.activeEntry = lastSelected
            session.selectEntry(lastSelected)
            updateActiveDetails(for: lastSelected)
        }
    }

    private func refreshColumns() {
        guard let index = session.entryIndex else {
            initializeColumns()
            return
        }

        var newNodes: [ColumnNode] = []
        var validActiveEntry: ArchiveEntry? = nil

        for node in columnNodes {
            let subs = (try? index.children(of: node.path, limit: 1000, includeAuxiliary: session.includeAuxiliary)) ?? []
            var selName = node.selectedName
            if let currentSel = selName, !subs.contains(where: { $0.name == currentSel }) {
                selName = nil
            }
            newNodes.append(ColumnNode(path: node.path, entries: subs, selectedName: selName))
            if let sel = selName, let matched = subs.first(where: { $0.name == sel }) {
                validActiveEntry = matched
            }
        }

        self.columnNodes = newNodes
        if let currentActive = activeEntry,
           let updated = try? index.entry(forID: currentActive.id) {
            self.activeEntry = updated
            updateActiveDetails(for: updated)
        } else if let valid = validActiveEntry {
            self.activeEntry = valid
            updateActiveDetails(for: valid)
        } else if let first = newNodes.first?.entries.first {
            self.activeEntry = first
            updateActiveDetails(for: first)
        } else {
            self.activeEntry = nil
            self.activeFolderSize = nil
        }
    }

    private func initializeColumns() {
        guard let index = session.entryIndex else {
            columnNodes = []
            activeEntry = nil
            return
        }

        let roots = (try? index.children(of: "", limit: 1000, includeAuxiliary: session.includeAuxiliary)) ?? []
        let initialPath = session.currentDirectoryPath
        var nodes: [ColumnNode] = [
            ColumnNode(path: "", entries: roots, selectedName: nil)
        ]

        if !initialPath.isEmpty {
            let parts = initialPath.split(separator: "/").map(String.init)
            var currentPath = ""
            for (idx, part) in parts.enumerated() {
                if idx < nodes.count {
                    nodes[idx].selectedName = part
                }
                currentPath = currentPath.isEmpty ? part : "\(currentPath)/\(part)"
                let subs = (try? index.children(of: currentPath, limit: 1000, includeAuxiliary: session.includeAuxiliary)) ?? []
                nodes.append(ColumnNode(path: currentPath, entries: subs, selectedName: nil))
            }
        }

        self.columnNodes = nodes

        if let first = roots.first {
            self.activeEntry = first
            session.selectEntry(first)
            updateActiveDetails(for: first)
        } else {
            self.activeEntry = nil
            session.selectEntry(nil)
        }
    }

    private func handleSelection(entry: ArchiveEntry, at columnIndex: Int) {
        guard columnIndex < columnNodes.count else { return }

        // If clicking the currently selected directory again in the same column, collapse its expanded child column
        if columnNodes[columnIndex].selectedName == entry.name && entry.type == .directory {
            columnNodes[columnIndex].selectedName = nil
            if columnIndex + 1 < columnNodes.count {
                columnNodes.removeSubrange((columnIndex + 1)...)
            }
            session.currentDirectoryPath = columnNodes[columnIndex].path
            activeEntry = entry
            session.selectEntry(entry)
            updateActiveDetails(for: entry)
            return
        }

        // Update selected name in current column
        columnNodes[columnIndex].selectedName = entry.name

        // Truncate any child columns beyond this one
        if columnIndex + 1 < columnNodes.count {
            columnNodes.removeSubrange((columnIndex + 1)...)
        }

        activeEntry = entry
        session.selectEntry(entry)
        updateActiveDetails(for: entry)

        if entry.type == .directory {
            session.currentDirectoryPath = entry.path
            // Expand next column for directory children
            if let index = session.entryIndex {
                let subs = (try? index.children(of: entry.path, limit: 1000, includeAuxiliary: session.includeAuxiliary)) ?? []
                columnNodes.append(ColumnNode(path: entry.path, entries: subs, selectedName: nil))
            }
        } else {
            session.currentDirectoryPath = columnNodes[columnIndex].path
        }
    }

    private func handleDoubleClick(entry: ArchiveEntry, at columnIndex: Int) {
        session.handleDoubleClick(on: entry)
    }

    private func updateActiveDetails(for entry: ArchiveEntry) {
        if entry.type == .directory {
            Task {
                let total = (try? session.entryIndex?.descendants(of: entry.path))?
                    .filter { $0.type != .directory }
                    .reduce(0) { $0 + $1.uncompressedSize } ?? 0
                await MainActor.run {
                    self.activeFolderSize = total
                }
            }
        } else {
            self.activeFolderSize = nil
        }
    }
}

// MARK: - Single Column List in Miller Columns

private struct ColumnListView: View {
    let node: EntryColumnBrowserView.ColumnNode
    let columnIndex: Int
    let onSelect: (ArchiveEntry) -> Void
    let onDoubleClick: (ArchiveEntry) -> Void
    @ObservedObject var session: ArchiveBrowsingSession

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 1) {
                ForEach(node.entries) { entry in
                    let isSelected = node.selectedName == entry.name
                    HStack(spacing: 7) {
                        Image(nsImage: nativeFinderIcon(for: entry, size: 16))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)

                        Text(entry.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(isSelected ? .white : .primary)

                        Spacer()

                        if entry.type == .directory {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : Color(NSColor.tertiaryLabelColor))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onDoubleClick(entry)
                    }
                    .onTapGesture(count: 1) {
                        onSelect(entry)
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

                        Button("解压此项") {
                            if let archiveURL = session.currentArchiveURL {
                                Task {
                                    await session.extractArchive(entries: [entry], to: archiveURL.deletingLastPathComponent())
                                }
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
            .padding(.top, 6)
            .padding(.horizontal, 6)
            .padding(.bottom, 75)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
    }
}

// MARK: - Helpers

public func fileSystemIconName(for entry: ArchiveEntry) -> String {
    if entry.type == .directory { return "folder.fill" }
    let ext = (entry.name as NSString).pathExtension.lowercased()
    switch ext {
    case "mov", "mp4", "m4v", "avi", "mkv": return "film"
    case "pdf": return "doc.richtext"
    case "txt", "rtf": return "doc.plaintext"
    case "md", "markdown": return "doc.text"
    case "jpg", "jpeg", "png", "heic", "webp", "gif": return "photo"
    case "zip", "7z", "rar", "tar", "gz": return "doc.zipper"
    case "app": return "app.fill"
    case "mp3", "m4a", "wav", "flac", "aac": return "music.note"
    case "doc", "docx": return "doc.text.fill"
    case "xls", "xlsx": return "tablecells"
    case "ppt", "pptx": return "chart.bar.doc.horizontal"
    case "swift", "py", "sh", "js", "ts", "json": return "chevron.left.forwardslash.chevron.right"
    default: return "doc"
    }
}

public func fileSystemIconColor(for entry: ArchiveEntry) -> Color {
    if entry.type == .directory { return Color.accentColor }
    let ext = (entry.name as NSString).pathExtension.lowercased()
    switch ext {
    case "mov", "mp4", "m4v", "avi", "mkv": return .cyan
    case "pdf": return .red
    case "jpg", "jpeg", "png", "heic", "webp", "gif": return .teal
    case "zip", "7z", "rar", "tar", "gz": return .orange
    case "app": return .blue
    case "mp3", "m4a", "wav", "flac": return .pink
    case "doc", "docx": return .blue
    case "xls", "xlsx": return .green
    case "ppt", "pptx": return .orange
    case "swift", "py", "sh", "js", "ts", "json": return .indigo
    default: return .secondary
    }
}

public func systemKind(for entry: ArchiveEntry) -> String {
    if entry.type == .directory { return "文件夹" }
    let ext = (entry.name as NSString).pathExtension.lowercased()
    switch ext {
    case "mov", "mp4", "m4v", "avi", "mkv": return "QuickTime 影片"
    case "pdf": return "PDF 文稿"
    case "txt": return "纯文本文稿"
    case "rtf": return "多信息文稿"
    case "md", "markdown": return "Markdown 文稿"
    case "jpg", "jpeg", "png", "heic", "webp", "gif": return "图像文件"
    case "zip", "7z", "rar", "tar", "gz": return "压缩归档"
    case "app": return "应用程序"
    case "doc", "docx": return "Microsoft Word 文稿"
    case "xls", "xlsx": return "Microsoft Excel 工作表"
    case "ppt", "pptx": return "Microsoft PowerPoint 演示文稿"
    case "swift": return "Swift 源代码"
    case "json": return "JSON 数据"
    default: return ext.isEmpty ? "文稿" : "\(ext.uppercased()) 文稿"
    }
}

public func nativeFinderIcon(for entry: ArchiveEntry, size: CGFloat = 64) -> NSImage {
    let base: NSImage
    if entry.type == .directory {
        if entry.name.hasSuffix(".app") {
            base = NSWorkspace.shared.icon(for: .applicationBundle)
        } else {
            base = NSWorkspace.shared.icon(for: .folder)
        }
    } else {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        let ut = UTType(filenameExtension: ext) ?? .data
        base = NSWorkspace.shared.icon(for: ut)
    }
    let copy = (base.copy() as? NSImage) ?? base
    copy.size = NSSize(width: size, height: size)
    return copy
}

@MainActor
public enum PureZipDateFormatter {
    public static let entryListFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年M月d日 H:mm"
        return fmt
    }()
}

@MainActor
public func entryDateFormatted(entry: ArchiveEntry) -> String {
    guard let date = entry.modifiedAt else { return "--" }
    return PureZipDateFormatter.entryListFormatter.string(from: date)
}
