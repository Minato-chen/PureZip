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
        GeometryReader { geo in
            ScrollViewReader { proxy in
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
                            .id(entry.id)
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
                .onChange(of: session.selectedEntryID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: nil)
                        }
                    }
                }
            }
            .onAppear {
                updateColumnCount(width: geo.size.width)
            }
            .onChange(of: geo.size.width) { _, newWidth in
                updateColumnCount(width: newWidth)
            }
        }
    }

    private func updateColumnCount(width: CGFloat) {
        let available = max(0, width - 40)
        let itemWidth: CGFloat = 108 + 16
        session.gridColumnCount = max(1, Int(available / itemWidth))
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
            let nameNFC = entry.name.precomposedStringWithCanonicalMapping
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let stripped = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let altURL = lease.url.appendingPathComponent(stripped)
                if FileManager.default.fileExists(atPath: altURL.path) {
                    fileURL = altURL
                } else if let enumerator = FileManager.default.enumerator(at: lease.url, includingPropertiesForKeys: nil) {
                    while let item = enumerator.nextObject() {
                        if let itemURL = item as? URL, itemURL.lastPathComponent.precomposedStringWithCanonicalMapping == nameNFC {
                            fileURL = itemURL
                            break
                        }
                    }
                }
            }

            if !FileManager.default.fileExists(atPath: fileURL.path) && archiveURL.pathExtension.lowercased() == "zip" {
                try? await ZIPEngine().extract(archiveURL, entries: [entry], to: lease.url)
                if !FileManager.default.fileExists(atPath: fileURL.path),
                   let enumerator = FileManager.default.enumerator(at: lease.url, includingPropertiesForKeys: nil) {
                    while let item = enumerator.nextObject() {
                        if let itemURL = item as? URL, itemURL.lastPathComponent.precomposedStringWithCanonicalMapping == nameNFC {
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
                    representationTypes: .all
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

@MainActor
public final class ColumnBrowserState: ObservableObject {
    public struct ColumnNode: Identifiable {
        public let id = UUID()
        public let path: String
        public var entries: [ArchiveEntry]
        public var totalCount: Int
        public var selectedName: String?
        public var isLoadingMore: Bool = false
        public var width: CGFloat

        public init(
            path: String,
            entries: [ArchiveEntry],
            totalCount: Int,
            selectedName: String?,
            isLoadingMore: Bool = false,
            width: CGFloat = 220
        ) {
            self.path = path
            self.entries = entries
            self.totalCount = totalCount
            self.selectedName = selectedName
            self.isLoadingMore = isLoadingMore
            self.width = width
        }
    }

    @Published public var columnNodes: [ColumnNode] = []
    @Published public var focusedColumnIndex: Int = 0
    @Published public var activeEntry: ArchiveEntry? = nil
    @Published public var activeFolderSize: Int64? = nil
    @Published public var columnWidth: CGFloat = 220
    public var currentColumnPath: String = ""

    private let pageSize: Int = 300
    private var childLoadTask: Task<Void, Never>? = nil

    public init() {}

    public func initializeColumns(session: ArchiveBrowsingSession) {
        childLoadTask?.cancel()
        guard let index = session.entryIndex else {
            columnNodes = []
            focusedColumnIndex = 0
            activeEntry = nil
            activeFolderSize = nil
            currentColumnPath = ""
            return
        }

        let totalRoots = (try? index.childCount(of: "", includeAuxiliary: session.includeAuxiliary)) ?? 0
        let roots = (try? index.children(of: "", offset: 0, limit: pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []
        let initialPath = session.currentDirectoryPath
        currentColumnPath = initialPath
        var nodes: [ColumnNode] = [
            ColumnNode(path: "", entries: roots, totalCount: totalRoots, selectedName: nil, width: self.columnWidth)
        ]

        if !initialPath.isEmpty {
            let parts = initialPath.split(separator: "/").map(String.init)
            var currentPath = ""
            for (idx, part) in parts.enumerated() {
                if idx < nodes.count {
                    nodes[idx].selectedName = part
                }
                currentPath = currentPath.isEmpty ? part : "\(currentPath)/\(part)"
                let total = (try? index.childCount(of: currentPath, includeAuxiliary: session.includeAuxiliary)) ?? 0
                let subs = (try? index.children(of: currentPath, offset: 0, limit: pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []
                nodes.append(ColumnNode(path: currentPath, entries: subs, totalCount: total, selectedName: nil, width: self.columnWidth))
            }
        }

        self.columnNodes = nodes
        self.focusedColumnIndex = max(0, nodes.count - 1)

        if let first = roots.first {
            self.activeEntry = first
            session.selectEntry(first)
            updateActiveDetails(for: first, session: session)
        } else {
            self.activeEntry = nil
            session.selectEntry(nil)
        }
    }

    public func syncColumnsToCurrentDirectory(path: String, session: ArchiveBrowsingSession) {
        childLoadTask?.cancel()
        guard let index = session.entryIndex else { return }
        currentColumnPath = path

        if path.isEmpty {
            let totalRoots = (try? index.childCount(of: "", includeAuxiliary: session.includeAuxiliary)) ?? 0
            let roots = (try? index.children(of: "", offset: 0, limit: pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []
            self.columnNodes = [
                ColumnNode(path: "", entries: roots, totalCount: totalRoots, selectedName: nil, width: self.columnWidth)
            ]
            self.focusedColumnIndex = 0
            if let first = roots.first {
                self.activeEntry = first
                session.selectEntry(first)
                updateActiveDetails(for: first, session: session)
            } else {
                self.activeEntry = nil
                self.activeFolderSize = nil
            }
            return
        }

        let currentLeafPath = columnNodes.last?.path ?? ""
        if currentLeafPath == path { return }

        let totalRoots = (try? index.childCount(of: "", includeAuxiliary: session.includeAuxiliary)) ?? 0
        let roots = (try? index.children(of: "", offset: 0, limit: pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []
        var nodes: [ColumnNode] = [
            ColumnNode(path: "", entries: roots, totalCount: totalRoots, selectedName: nil, width: self.columnWidth)
        ]

        let parts = path.split(separator: "/").map(String.init)
        var currentPath = ""
        for (idx, part) in parts.enumerated() {
            if idx < nodes.count {
                nodes[idx].selectedName = part
            }
            currentPath = currentPath.isEmpty ? part : "\(currentPath)/\(part)"
            let total = (try? index.childCount(of: currentPath, includeAuxiliary: session.includeAuxiliary)) ?? 0
            let subs = (try? index.children(of: currentPath, offset: 0, limit: pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []
            nodes.append(ColumnNode(path: currentPath, entries: subs, totalCount: total, selectedName: nil, width: self.columnWidth))
        }

        self.columnNodes = nodes
        if let lastNode = nodes.last, !lastNode.entries.isEmpty {
            self.focusedColumnIndex = max(0, nodes.count - 1)
            if let lastSelected = lastNode.entries.first {
                self.activeEntry = lastSelected
                session.selectEntry(lastSelected)
                updateActiveDetails(for: lastSelected, session: session)
            }
        } else {
            self.focusedColumnIndex = max(0, nodes.count - 2)
            self.activeEntry = nil
            self.activeFolderSize = nil
        }
    }

    public func handleSelection(entry: ArchiveEntry, at columnIndex: Int, session: ArchiveBrowsingSession, debounceChild: Bool = false) {
        guard columnIndex < columnNodes.count else { return }
        focusedColumnIndex = columnIndex

        columnNodes[columnIndex].selectedName = entry.name
        if columnIndex + 1 < columnNodes.count {
            columnNodes.removeSubrange((columnIndex + 1)...)
        }

        activeEntry = entry
        session.selectEntry(entry)
        updateActiveDetails(for: entry, session: session)

        childLoadTask?.cancel()

        if entry.type == .directory {
            currentColumnPath = entry.path
            session.currentDirectoryPath = entry.path
            guard let index = session.entryIndex else { return }

            if debounceChild {
                childLoadTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard !Task.isCancelled else { return }
                    let total = (try? index.childCount(of: entry.path, includeAuxiliary: session.includeAuxiliary)) ?? 0
                    let subs = (try? index.children(of: entry.path, offset: 0, limit: self.pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []
                    if columnIndex + 1 < self.columnNodes.count {
                        self.columnNodes.removeSubrange((columnIndex + 1)...)
                    }
                    self.columnNodes.append(ColumnNode(path: entry.path, entries: subs, totalCount: total, selectedName: nil, width: self.columnWidth))
                }
            } else {
                let total = (try? index.childCount(of: entry.path, includeAuxiliary: session.includeAuxiliary)) ?? 0
                let subs = (try? index.children(of: entry.path, offset: 0, limit: pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []
                columnNodes.append(ColumnNode(path: entry.path, entries: subs, totalCount: total, selectedName: nil, width: self.columnWidth))
            }
        } else {
            currentColumnPath = columnNodes[columnIndex].path
            session.currentDirectoryPath = columnNodes[columnIndex].path
        }
    }

    public func loadMoreEntries(at columnIndex: Int, session: ArchiveBrowsingSession) {
        guard columnIndex < columnNodes.count else { return }
        guard !columnNodes[columnIndex].isLoadingMore else { return }
        let currentCount = columnNodes[columnIndex].entries.count
        guard currentCount < columnNodes[columnIndex].totalCount else { return }
        guard let index = session.entryIndex else { return }

        columnNodes[columnIndex].isLoadingMore = true
        let nodePath = columnNodes[columnIndex].path

        Task { @MainActor in
            let more = (try? index.children(
                of: nodePath,
                offset: currentCount,
                limit: self.pageSize,
                includeAuxiliary: session.includeAuxiliary
            )) ?? []
            if columnIndex < self.columnNodes.count {
                self.columnNodes[columnIndex].entries.append(contentsOf: more)
                self.columnNodes[columnIndex].isLoadingMore = false
            }
        }
    }

    public func navigate(direction: ArchiveBrowsingSession.NavigationDirection, session: ArchiveBrowsingSession) -> Bool {
        guard !columnNodes.isEmpty else { return false }
        let colIdx = max(0, min(focusedColumnIndex, columnNodes.count - 1))

        // Scheme B: Arrow keys strictly navigate within the current column. They NEVER change hierarchy!
        switch direction {
        case .left, .right:
            return false

        case .up, .down:
            let node = columnNodes[colIdx]
            let entries = node.entries
            guard !entries.isEmpty else { return false }

            let currentIdx = node.selectedName.flatMap { name in entries.firstIndex(where: { $0.name == name }) }

            if direction == .up {
                let newIdx = currentIdx.map { max(0, $0 - 1) } ?? (entries.count - 1)
                handleSelection(entry: entries[newIdx], at: colIdx, session: session, debounceChild: true)
                return true
            } else {
                let newIdx = currentIdx.map { min(entries.count - 1, $0 + 1) } ?? 0
                if newIdx >= entries.count - 3 && entries.count < node.totalCount {
                    loadMoreEntries(at: colIdx, session: session)
                }
                handleSelection(entry: entries[newIdx], at: colIdx, session: session, debounceChild: true)
                return true
            }
        }
    }

    @discardableResult
    public func enterChildColumn(session: ArchiveBrowsingSession) -> Bool {
        guard !columnNodes.isEmpty else { return false }
        let colIdx = max(0, min(focusedColumnIndex, columnNodes.count - 1))
        let node = columnNodes[colIdx]

        guard let selName = node.selectedName,
              let entry = node.entries.first(where: { $0.name == selName }),
              entry.type == .directory else {
            return false
        }

        guard let index = session.entryIndex else { return false }

        // Cancel any pending debounce task and load child column immediately
        childLoadTask?.cancel()
        let total = (try? index.childCount(of: entry.path, includeAuxiliary: session.includeAuxiliary)) ?? 0
        let subs = (try? index.children(of: entry.path, offset: 0, limit: pageSize, includeAuxiliary: session.includeAuxiliary)) ?? []

        if colIdx + 1 < columnNodes.count {
            columnNodes.removeSubrange((colIdx + 1)...)
        }
        columnNodes.append(ColumnNode(path: entry.path, entries: subs, totalCount: total, selectedName: nil, width: self.columnWidth))

        focusedColumnIndex = colIdx + 1
        currentColumnPath = entry.path
        session.currentDirectoryPath = entry.path

        if let firstChild = subs.first {
            handleSelection(entry: firstChild, at: colIdx + 1, session: session, debounceChild: false)
        } else {
            activeEntry = nil
            session.selectEntry(nil)
            activeFolderSize = nil
        }
        return true
    }

    @discardableResult
    public func exitToParentColumn(session: ArchiveBrowsingSession) -> Bool {
        guard !columnNodes.isEmpty else { return false }
        let colIdx = max(0, min(focusedColumnIndex, columnNodes.count - 1))

        if colIdx > 0 {
            focusedColumnIndex = colIdx - 1
            let parentNode = columnNodes[colIdx - 1]
            currentColumnPath = parentNode.path
            session.currentDirectoryPath = parentNode.path

            if let sel = parentNode.selectedName, let matched = parentNode.entries.first(where: { $0.name == sel }) {
                activeEntry = matched
                session.selectEntry(matched)
                updateActiveDetails(for: matched, session: session)
            }
            return true
        }
        return false
    }

    public func updateActiveDetails(for entry: ArchiveEntry, session: ArchiveBrowsingSession) {
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

public struct EntryColumnBrowserView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @ObservedObject private var state: ColumnBrowserState

    public init(session: ArchiveBrowsingSession) {
        self.session = session
        self._state = ObservedObject(wrappedValue: session.columnBrowserState)
    }

    public var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(Array(state.columnNodes.enumerated()), id: \.element.id) { index, node in
                            ColumnListView(
                                node: node,
                                columnIndex: index,
                                isFocused: index == state.focusedColumnIndex,
                                onSelect: { entry in
                                    state.handleSelection(entry: entry, at: index, session: session, debounceChild: false)
                                },
                                onDoubleClick: { entry in
                                    session.handleDoubleClick(on: entry)
                                },
                                onLoadMore: {
                                    state.loadMoreEntries(at: index, session: session)
                                },
                                session: session
                            )
                            .frame(width: node.width, height: geo.size.height)
                            .id(node.id)

                            ColumnResizeHandle(columnIndex: index, state: state)
                                .id("resize-\(node.id)")
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, maxHeight: geo.size.height, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
                .onChange(of: state.columnNodes.count) {
                    scrollToAppropriateColumn(proxy: proxy, viewportWidth: geo.size.width)
                }
                .onChange(of: state.focusedColumnIndex) { _, newIdx in
                    if newIdx < state.columnNodes.count {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(state.columnNodes[newIdx].id, anchor: .trailing)
                        }
                    }
                }
                .onChange(of: session.currentDirectoryPath) { _, newPath in
                    if state.currentColumnPath == newPath { return }
                    state.syncColumnsToCurrentDirectory(path: newPath, session: session)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToAppropriateColumn(proxy: proxy, viewportWidth: geo.size.width)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            state.initializeColumns(session: session)
        }
        .onChange(of: session.currentArchiveURL) {
            state.initializeColumns(session: session)
        }
        .onChange(of: session.indexRevision) {
            state.initializeColumns(session: session)
        }
    }

    private func scrollToAppropriateColumn(proxy: ScrollViewProxy, viewportWidth: CGFloat) {
        let totalWidth = state.columnNodes.reduce(0) { $0 + $1.width + 1 }
        if totalWidth > viewportWidth {
            if let lastID = state.columnNodes.last?.id {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(lastID, anchor: .trailing)
                }
            }
        } else {
            if let firstID = state.columnNodes.first?.id {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(firstID, anchor: .leading)
                }
            }
        }
    }
}

// MARK: - Column Resizable Split Handle

private struct ColumnResizeHandle: View {
    let columnIndex: Int
    @ObservedObject var state: ColumnBrowserState
    @State private var dragStartWidth: CGFloat? = nil
    @State private var isDragging: Bool = false
    @State private var isCursorPushed: Bool = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isDragging ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.45))
                .frame(width: 1)

            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStartWidth == nil {
                                isDragging = true
                                dragStartWidth = columnIndex < state.columnNodes.count ? state.columnNodes[columnIndex].width : state.columnWidth
                            }
                            let start = dragStartWidth ?? state.columnWidth
                            let target = max(160, min(550, start + value.translation.width))
                            var transaction = Transaction()
                            transaction.animation = nil
                            withTransaction(transaction) {
                                if NSEvent.modifierFlags.contains(.option) {
                                    state.columnWidth = target
                                    for i in state.columnNodes.indices {
                                        state.columnNodes[i].width = target
                                    }
                                } else {
                                    if columnIndex < state.columnNodes.count {
                                        state.columnNodes[columnIndex].width = target
                                    }
                                }
                            }
                        }
                        .onEnded { _ in
                            dragStartWidth = nil
                            isDragging = false
                            if isCursorPushed {
                                NSCursor.pop()
                                isCursorPushed = false
                            }
                        }
                )
        }
        .frame(maxHeight: .infinity)
        .onHover { hovering in
            if hovering || isDragging {
                if !isCursorPushed {
                    NSCursor.resizeLeftRight.push()
                    isCursorPushed = true
                }
            } else {
                if isCursorPushed && !isDragging {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
        }
    }
}

// MARK: - Single Column List in Miller Columns

private struct ColumnListView: View {
    let node: ColumnBrowserState.ColumnNode
    let columnIndex: Int
    let isFocused: Bool
    let onSelect: (ArchiveEntry) -> Void
    let onDoubleClick: (ArchiveEntry) -> Void
    let onLoadMore: () -> Void
    @ObservedObject var session: ArchiveBrowsingSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                if node.entries.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "folder")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        Text("文件夹为空")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(node.entries) { entry in
                            let isSelected = node.selectedName == entry.name
                            ColumnEntryRow(
                                entry: entry,
                                isSelected: isSelected,
                                isFocused: isFocused,
                                onSelect: { onSelect(entry) },
                                onDoubleClick: { onDoubleClick(entry) },
                                session: session
                            )
                            .id(entry.id)
                            .onAppear {
                                if entry.id == node.entries.last?.id && node.entries.count < node.totalCount {
                                    onLoadMore()
                                }
                            }
                        }

                        if node.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 14)
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(isFocused ? 0.45 : 0.25))
            .onChange(of: node.selectedName) { _, newSel in
                if let sel = newSel, let matched = node.entries.first(where: { $0.name == sel }) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(matched.id, anchor: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Column Entry Row View (Clean Finder Standard 26px Height)

private struct ColumnEntryRow: View {
    let entry: ArchiveEntry
    let isSelected: Bool
    let isFocused: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    @ObservedObject var session: ArchiveBrowsingSession

    var body: some View {
        HStack(spacing: 6) {
            ArchiveEntryRowIconView(entry: entry)
                .frame(width: 16, height: 16)

            Text(entry.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()

            if entry.type == .directory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : Color(NSColor.tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? (isFocused ? Color.accentColor : Color.accentColor.opacity(0.65)) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .onHover { isHovered in
            HoverPreviewCoordinator.shared.onRowHover(entry: entry, isHovered: isHovered, session: session)
        }
        .onDrag {
            ArchiveDragExportManager.shared.itemProvider(for: entry, session: session)
        }
        .help(entry.name)
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
