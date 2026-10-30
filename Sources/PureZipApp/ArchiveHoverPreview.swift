import AppKit
import SwiftUI
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import WebKit
import SceneKit
import CryptoKit
import ArchiveCore
import ArchiveEngines

/// Candidate entry and cursor position for hover preview.
public struct HoverPreviewCandidate: Identifiable, Equatable, Sendable {
    public var id: String { entry.id }
    public let entry: ArchiveEntry
    public let position: CGPoint

    public static func == (lhs: HoverPreviewCandidate, rhs: HoverPreviewCandidate) -> Bool {
        lhs.entry.id == rhs.entry.id
    }
}

/// In-memory artifact cache for hover and inspector previews.
public final class PreviewArtifactCache {
    public static let shared = PreviewArtifactCache()
    private let imageCache = NSCache<NSString, NSImage>()
    private let pdfPagesCache = NSCache<NSString, NSArray>()
    private let textCache = NSCache<NSString, NSString>()
    private let dimensionsCache = NSCache<NSString, NSValue>()

    public init() {
        imageCache.countLimit = 120
        pdfPagesCache.countLimit = 30
        textCache.countLimit = 200
        dimensionsCache.countLimit = 500
    }

    public func image(for key: String) -> NSImage? {
        imageCache.object(forKey: key as NSString)
    }
    public func setImage(_ image: NSImage, for key: String) {
        imageCache.setObject(image, forKey: key as NSString)
    }

    public func pdfPages(for key: String) -> [NSImage]? {
        pdfPagesCache.object(forKey: key as NSString) as? [NSImage]
    }
    public func setPdfPages(_ pages: [NSImage], for key: String) {
        pdfPagesCache.setObject(pages as NSArray, forKey: key as NSString)
    }

    public func text(for key: String) -> String? {
        textCache.object(forKey: key as NSString) as String?
    }
    public func setText(_ text: String, for key: String) {
        textCache.setObject(text as NSString, forKey: key as NSString)
    }

    public func dimensions(for key: String) -> CGSize? {
        dimensionsCache.object(forKey: key as NSString)?.sizeValue
    }
    public func setDimensions(_ size: CGSize, for key: String) {
        dimensionsCache.setObject(NSValue(size: size), forKey: key as NSString)
    }

    private final class AudioBox: NSObject {
        let data: AudioPreviewData
        init(_ data: AudioPreviewData) { self.data = data }
    }
    private final class VideoBox: NSObject {
        let data: VideoPreviewData
        init(_ data: VideoPreviewData) { self.data = data }
    }
    private final class NestedSummaryBox: NSObject {
        let summary: ArchiveBrowsingSession.NestedArchivePreviewSummary
        init(_ summary: ArchiveBrowsingSession.NestedArchivePreviewSummary) { self.summary = summary }
    }

    // Cache for AudioPreviewData, VideoPreviewData, and NestedArchivePreviewSummary with strict count limits
    private let audioCache: NSCache<NSString, AudioBox> = {
        let c = NSCache<NSString, AudioBox>()
        c.countLimit = 30
        return c
    }()
    private let videoCache: NSCache<NSString, VideoBox> = {
        let c = NSCache<NSString, VideoBox>()
        c.countLimit = 15
        return c
    }()
    private let nestedSummaryCache: NSCache<NSString, NestedSummaryBox> = {
        let c = NSCache<NSString, NestedSummaryBox>()
        c.countLimit = 50
        return c
    }()

    public func audioData(for key: String) -> AudioPreviewData? {
        audioCache.object(forKey: key as NSString)?.data
    }
    public func setAudioData(_ data: AudioPreviewData, for key: String) {
        audioCache.setObject(AudioBox(data), forKey: key as NSString)
    }

    public func videoData(for key: String) -> VideoPreviewData? {
        videoCache.object(forKey: key as NSString)?.data
    }
    public func setVideoData(_ data: VideoPreviewData, for key: String) {
        videoCache.setObject(VideoBox(data), forKey: key as NSString)
    }

    public func nestedArchiveSummary(for key: String) -> ArchiveBrowsingSession.NestedArchivePreviewSummary? {
        nestedSummaryCache.object(forKey: key as NSString)?.summary
    }
    public func setNestedArchiveSummary(_ summary: ArchiveBrowsingSession.NestedArchivePreviewSummary, for key: String) {
        nestedSummaryCache.setObject(NestedSummaryBox(summary), forKey: key as NSString)
    }

    // Shared disk cache for extracted media/document preview files so Hover, Inspector, and Spacebar QuickLook
    // share a single extraction instead of re-extracting large video/audio files multiple times.
    private let fileCacheLock = NSLock()
    private var extractedFileCache: [String: URL] = [:]
    private var extractedFileOrder: [String] = []
    private let maxCachedExtractedFiles = 12
    private var inFlightExtractions: [String: Task<URL, Error>] = [:]
    private let previewMediaCacheDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PureZipSharedPreviewMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public func cachedExtractedFile(for key: String) -> URL? {
        fileCacheLock.lock()
        defer { fileCacheLock.unlock() }
        if let url = extractedFileCache[key], FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        extractedFileCache.removeValue(forKey: key)
        extractedFileOrder.removeAll { $0 == key }
        return nil
    }

    public func storeExtractedFile(from sourceURL: URL, for key: String, fileExtension: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(24)
        let extPart = fileExtension.isEmpty ? "bin" : fileExtension
        let destURL = previewMediaCacheDir.appendingPathComponent("media_\(digest).\(extPart)")

        fileCacheLock.lock()
        if let existing = extractedFileCache[key], FileManager.default.fileExists(atPath: existing.path) {
            fileCacheLock.unlock()
            return existing
        }
        fileCacheLock.unlock()

        let fm = FileManager.default
        try? fm.createDirectory(at: previewMediaCacheDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destURL.path) {
            try? fm.removeItem(at: destURL)
        }
        do {
            try fm.moveItem(at: sourceURL, to: destURL)
        } catch {
            do {
                try fm.copyItem(at: sourceURL, to: destURL)
            } catch {
                return nil
            }
        }

        fileCacheLock.lock()
        defer { fileCacheLock.unlock() }
        extractedFileCache[key] = destURL
        extractedFileOrder.removeAll { $0 == key }
        extractedFileOrder.append(key)
        while extractedFileOrder.count > maxCachedExtractedFiles {
            let oldestKey = extractedFileOrder.removeFirst()
            if let oldURL = extractedFileCache.removeValue(forKey: oldestKey) {
                try? fm.removeItem(at: oldURL)
            }
        }
        return destURL
    }

    /// Extracts an archive entry once and shares the resulting file across concurrent Hover, Inspector, and QuickLook tasks.
    public func sharedExtractedFile(
        for entry: ArchiveEntry,
        in archiveURL: URL,
        broker: ArchiveEngineBroker
    ) async throws -> URL {
        let key = "\(archiveURL.path):\(entry.path)"
        if let cached = cachedExtractedFile(for: key) {
            return cached
        }

        let task: Task<URL, Error> = {
            fileCacheLock.lock()
            defer { fileCacheLock.unlock() }
            if let existingTask = inFlightExtractions[key] {
                return existingTask
            }
            let newTask = Task<URL, Error> {
                let lease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "shared-preview")
                defer { lease.release() }
                try await broker.extract(archiveURL, entries: [entry], to: lease.url)

                var extractedURL = lease.url.appendingPathComponent(entry.path)
                if !FileManager.default.fileExists(atPath: extractedURL.path) {
                    let stripped = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let alt = lease.url.appendingPathComponent(stripped)
                    if FileManager.default.fileExists(atPath: alt.path) {
                        extractedURL = alt
                    } else if let enumerator = FileManager.default.enumerator(at: lease.url, includingPropertiesForKeys: nil) {
                        while let item = enumerator.nextObject() {
                            if let obj = item as? URL, obj.lastPathComponent == entry.name {
                                extractedURL = obj
                                break
                            }
                        }
                    }
                }

                guard FileManager.default.fileExists(atPath: extractedURL.path) else {
                    throw ArchiveEngineError.io("Preview file not found after extraction: \(entry.name)")
                }

                let ext = (entry.name as NSString).pathExtension.lowercased()
                if let stored = self.storeExtractedFile(from: extractedURL, for: key, fileExtension: ext) {
                    return stored
                }
                return extractedURL
            }
            inFlightExtractions[key] = newTask
            return newTask
        }()

        do {
            let result = try await task.value
            fileCacheLock.withLock {
                _ = inFlightExtractions.removeValue(forKey: key)
            }
            return result
        } catch {
            fileCacheLock.withLock {
                _ = inFlightExtractions.removeValue(forKey: key)
            }
            throw error
        }
    }
}

/// Floating HUD panel controller for archive hover previews.
@MainActor
public final class ArchiveHoverPreviewPanelController {
    public static let shared = ArchiveHoverPreviewPanelController()

    public private(set) var panel: NSPanel?
    private var activeEntryID: String?

    private init() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        // Keep preview panel at floating level, beneath contextual popup menus (.popUpMenu)
        p.level = .floating
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        self.panel = p
    }

    public static func isSupportedPreview(ext: String, entry: ArchiveEntry? = nil) -> Bool {
        if entry?.isNestedArchive == true {
            return true
        }
        if MediaPreviewExtractor.isVideo(ext: ext) || MediaPreviewExtractor.isAudio(ext: ext) {
            return true
        }
        let supportedMedia: Set<String> = [
            "png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "tiff", "ico",
            "pdf",
            "docx", "xlsx", "pptx", "pages", "numbers", "key",
            "glb", "gltf", "usdz", "usd", "obj", "dae", "scn", "stl", "ply", "abc"
        ]
        let supportedText: Set<String> = [
            "txt", "md", "markdown", "mdown", "json", "xml", "plist", "yml", "yaml", "toml",
            "swift", "c", "cpp", "cc", "cxx", "h", "hpp", "m", "mm", "py", "sh", "zsh", "bash",
            "js", "jsx", "ts", "tsx", "html", "htm", "css", "scss", "sass", "less", "rs", "go",
            "java", "kt", "kts", "rb", "php", "sql", "log", "ini", "conf", "cfg", "env", "properties",
            "gradle", "cmake", "make", "dockerfile", "gitignore", "gitattributes", "svg", "csv", "tsv", "mtl"
        ]
        return supportedMedia.contains(ext) || supportedText.contains(ext)
    }

    public func show(entry: ArchiveEntry, session: ArchiveBrowsingSession, at screenPoint: CGPoint) {
        guard let panel = panel else { return }
        let ext = (entry.name as NSString).pathExtension.lowercased()

        // Only show hover preview for supported file types
        guard ArchiveHoverPreviewPanelController.isSupportedPreview(ext: ext, entry: entry) else {
            hide()
            return
        }

        self.activeEntryID = entry.id

        var isImage = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "tiff", "ico"].contains(ext)
        var isPDF = ext == "pdf"
        let isOffice = ["docx", "xlsx", "pptx", "pages", "numbers", "key"].contains(ext)
        let is3D = ["glb", "gltf", "obj", "dae", "usdz", "usd", "scn", "stl", "ply", "abc"].contains(ext)
        let isVideo = MediaPreviewExtractor.isVideo(ext: ext)
        let isAudio = MediaPreviewExtractor.isAudio(ext: ext)
        let isNested = entry.isNestedArchive

        // Auto-detect based on cached artifact if extension is ambiguous or missing
        let cacheKey = "\(session.currentArchiveURL?.path ?? ""):\(entry.path)"
        if !isImage && PreviewArtifactCache.shared.image(for: cacheKey) != nil {
            isImage = true
        }
        if !isPDF && PreviewArtifactCache.shared.pdfPages(for: cacheKey) != nil {
            isPDF = true
        }

        // Direct borderless floating HUD for images, PDFs and Office docs
        let isFrameless = isImage || isPDF || isOffice

        // Calculate card size
        let cardWidth: CGFloat = (is3D || isVideo) ? 460 : ((isAudio || isNested) ? 440 : (isFrameless ? 460 : 440))
        let cardHeight: CGFloat = is3D ? 380 : (isVideo ? 290 : (isAudio ? 230 : (isNested ? 270 : (isFrameless ? 420 : 330))))

        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let hosting = NSHostingView(rootView: HoverPreviewCardView(entry: entry, session: session))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: cardWidth, height: cardHeight))
        panel.setContentSize(NSSize(width: cardWidth, height: cardHeight))

        var origin = screenPoint
        origin.x += 24
        origin.y -= (cardHeight / 2)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.x + cardWidth + 16 > visible.maxX {
                origin.x = screenPoint.x - cardWidth - 24
            }
            if origin.y < visible.minY {
                origin.y = visible.minY + 12
            }
            if origin.y + cardHeight > visible.maxY {
                origin.y = visible.maxY - cardHeight - 12
            }
        }

        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
    }

    public func hide() {
        activeEntryID = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
    }
}

/// Coordinates the hover delay and smooth mouse transition between row and preview panel.
@MainActor
public final class HoverPreviewCoordinator: ObservableObject {
    public static let shared = HoverPreviewCoordinator()
    private var hoverTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var currentHoveredID: String?
    public private(set) var isPanelVisible: Bool = false
    public private(set) var isMenuTracking: Bool = false
    private weak var currentSession: ArchiveBrowsingSession?

    private var eventMonitor: Any?

    private init() {
        // Dismiss preview immediately when right click or middle click happens
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.hideAll()
            }
            return event
        }

        // Suppress and dismiss preview whenever a menu opens (context menu, popup menu, etc.)
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isMenuTracking = true
                self.hideAll()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isMenuTracking = false
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public func onRowHover(entry: ArchiveEntry, isHovered: Bool, session: ArchiveBrowsingSession) {
        currentSession = session
        guard PureZipPreferences.shared.hoverPreviewEnabled, !isMenuTracking else {
            hidePanel(session: session)
            return
        }
        guard entry.type != .directory else {
            if currentHoveredID == entry.id {
                hidePanel(session: session)
            }
            return
        }

        let ext = (entry.name as NSString).pathExtension.lowercased()
        guard ArchiveHoverPreviewPanelController.isSupportedPreview(ext: ext, entry: entry) else {
            if currentHoveredID == entry.id {
                hidePanel(session: session)
            }
            return
        }

        if isHovered {
            dismissTask?.cancel()
            currentHoveredID = entry.id
            hoverTask?.cancel()

            // KEY FOR "跟手" (Snappy cursor tracking):
            // If the preview is already showing for a previous item, switch INSTANTLY (20ms)
            // without making the user wait through the full initial delay again!
            let delayNanos: UInt64 = isPanelVisible ? 20_000_000 : 200_000_000

            hoverTask = Task { @MainActor in
                if delayNanos > 0 {
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
                guard !Task.isCancelled, self.currentHoveredID == entry.id, !self.isMenuTracking else { return }

                let mousePos = NSEvent.mouseLocation
                session.hoveredCandidate = HoverPreviewCandidate(entry: entry, position: mousePos)
                ArchiveHoverPreviewPanelController.shared.show(entry: entry, session: session, at: mousePos)
                self.isPanelVisible = true
            }
        } else {
            let leavingID = entry.id
            hoverTask?.cancel()
            dismissTask?.cancel()

            // Smooth debounce (120ms): allows cursor to glide smoothly across subviews, dividers,
            // or table rows without dropping the panel or causing high-frequency flicker.
            dismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                if self.currentHoveredID == leavingID {
                    self.hidePanel(session: session)
                }
            }
        }
    }

    public func hidePanel(session: ArchiveBrowsingSession?) {
        currentHoveredID = nil
        isPanelVisible = false
        hoverTask?.cancel()
        dismissTask?.cancel()
        ArchiveHoverPreviewPanelController.shared.hide()
        session?.hoveredCandidate = nil
    }

    public func hideAll() {
        hidePanel(session: currentSession)
    }
}

/// Observable preview state manager generating high-fidelity thumbnails (Images, PDFs, Markdown, Code, Office, Video, Audio).
@MainActor
public final class HoverPreviewViewModel: ObservableObject {
    @Published public var previewImage: NSImage?
    @Published public var imageDimensions: CGSize?
    @Published public var pdfPages: [NSImage] = []
    @Published public var quickLookThumbnail: NSImage?
    @Published public var previewText: String?
    @Published public var model3DURL: URL?
    @Published public var videoData: VideoPreviewData?
    @Published public var audioData: AudioPreviewData?
    @Published public var nestedSummary: ArchiveBrowsingSession.NestedArchivePreviewSummary?
    @Published public var isLoading = true

    public init() {}

    public func loadQuickPreview(for entry: ArchiveEntry, in session: ArchiveBrowsingSession) async {
        let cacheKey = "\(session.currentArchiveURL?.path ?? ""):\(entry.path)"
        if entry.isNestedArchive, let cachedSummary = PreviewArtifactCache.shared.nestedArchiveSummary(for: cacheKey) {
            self.nestedSummary = cachedSummary
            self.isLoading = false
            return
        }
        if let vData = PreviewArtifactCache.shared.videoData(for: cacheKey) {
            self.videoData = vData
            self.isLoading = false
            return
        }
        if let aData = PreviewArtifactCache.shared.audioData(for: cacheKey) {
            self.audioData = aData
            self.isLoading = false
            return
        }
        if let img = PreviewArtifactCache.shared.image(for: cacheKey) {
            self.previewImage = img
            self.imageDimensions = PreviewArtifactCache.shared.dimensions(for: cacheKey)
            self.isLoading = false
            return
        }
        if let pages = PreviewArtifactCache.shared.pdfPages(for: cacheKey) {
            self.pdfPages = pages
            self.previewImage = pages.first
            self.isLoading = false
            return
        }
        if let txt = PreviewArtifactCache.shared.text(for: cacheKey) {
            self.previewText = txt
            self.isLoading = false
            return
        }

        guard let archiveURL = session.currentArchiveURL, entry.type != .directory else {
            isLoading = false
            return
        }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        let isMedia = MediaPreviewExtractor.isVideo(ext: ext) || MediaPreviewExtractor.isAudio(ext: ext)
        let isNested = entry.isNestedArchive
        let maxLimit: Int64 = isMedia ? (2 * 1024 * 1024 * 1024) : (isNested ? (500 * 1024 * 1024) : (50 * 1024 * 1024))
        guard entry.uncompressedSize <= maxLimit else {
            isLoading = false
            return
        }

        do {
            let fileURL = try await PreviewArtifactCache.shared.sharedExtractedFile(
                for: entry,
                in: archiveURL,
                broker: session.broker
            )
            guard !Task.isCancelled else { return }

            // 0.0 Nested Archive Summary
            if isNested, let nestedDesc = entry.nestedArchiveDescriptor {
                var nestedEntries: [ArchiveEntry] = []
                var totalBytes: Int64 = 0
                if let stream = try? await session.broker.list(fileURL, password: nil) {
                    for try await batch in stream {
                        for item in batch where !item.isAuxiliary {
                            nestedEntries.append(item)
                            if item.type == .file {
                                totalBytes += max(0, item.uncompressedSize)
                            }
                        }
                    }
                }
                let summary = ArchiveBrowsingSession.NestedArchivePreviewSummary(
                    formatDisplayName: nestedDesc.displayName,
                    totalEntryCount: nestedEntries.count,
                    totalUncompressedBytes: totalBytes,
                    topEntries: Array(nestedEntries.prefix(8))
                )
                self.nestedSummary = summary
                PreviewArtifactCache.shared.setNestedArchiveSummary(summary, for: cacheKey)
                isLoading = false
                return
            }

            // 0. Video Files (Fast Progressive Low-Res Keyframe Skimmer)
            if MediaPreviewExtractor.isVideo(ext: ext) {
                let isLargeVideo = entry.uncompressedSize > (150 * 1024 * 1024)
                let frameCount = isLargeVideo ? 3 : 5
                let lowResTarget = CGSize(width: 360, height: 202)
                let vData = await MediaPreviewExtractor.extractVideoData(
                    from: fileURL,
                    maxKeyframes: frameCount,
                    targetSize: lowResTarget
                )
                self.videoData = vData
                PreviewArtifactCache.shared.setVideoData(vData, for: cacheKey)
            }
            // 0.5 Audio Files (Waveform & Metadata)
            else if MediaPreviewExtractor.isAudio(ext: ext) {
                let aData = await MediaPreviewExtractor.extractAudioData(from: fileURL, sampleCount: 50)
                self.audioData = aData
                PreviewArtifactCache.shared.setAudioData(aData, for: cacheKey)
            }
            // 1. Image Files
            else if ["png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "tiff", "ico"].contains(ext) {
                if let img = NSImage(contentsOf: fileURL) {
                    var dims = img.size
                    if let rep = img.representations.first {
                        dims = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                    }
                    self.previewImage = img
                    self.imageDimensions = dims
                    PreviewArtifactCache.shared.setImage(img, for: cacheKey)
                    PreviewArtifactCache.shared.setDimensions(dims, for: cacheKey)
                }
            }
            // 2. PDF Documents - High-Resolution Vector Rendering (Retina-ready)
            else if ext == "pdf", let pdfDoc = PDFDocument(url: fileURL) {
                var pages: [NSImage] = []
                let maxPages = min(pdfDoc.pageCount, 2)
                for i in 0..<maxPages {
                    if let page = pdfDoc.page(at: i) {
                        let highRes = renderHighResolutionPDFPage(page, targetWidth: 1024)
                        pages.append(highRes)
                    }
                }
                if !pages.isEmpty {
                    self.pdfPages = pages
                    self.previewImage = pages.first
                    PreviewArtifactCache.shared.setPdfPages(pages, for: cacheKey)
                }
            }
            // 3. Office & Keynote documents (via native QLThumbnailGenerator)
            else if ["docx", "xlsx", "pptx", "pages", "numbers", "key"].contains(ext) {
                let req = QLThumbnailGenerator.Request(
                    fileAt: fileURL,
                    size: CGSize(width: 512, height: 512),
                    scale: NSScreen.main?.backingScaleFactor ?? 2.0,
                    representationTypes: .thumbnail
                )
                let (rep, _) = await withCheckedContinuation { continuation in
                    QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, err in
                        continuation.resume(returning: (rep, err))
                    }
                }
                if let qlImg = rep?.nsImage {
                    self.quickLookThumbnail = qlImg
                    PreviewArtifactCache.shared.setImage(qlImg, for: cacheKey)
                }
            }
            // 3.5 3D Models (GLB / GLTF / OBJ / DAE / USDZ / STL / PLY / ABC / SCN)
            else if ["glb", "gltf", "obj", "dae", "usdz", "usd", "scn", "stl", "ply", "abc"].contains(ext) {
                self.model3DURL = fileURL
            }
            // 4. Text, Markdown, JSON, Code, Configuration
            if self.previewImage == nil && self.pdfPages.isEmpty && self.quickLookThumbnail == nil && self.videoData == nil && self.audioData == nil && self.model3DURL == nil {
                if let fh = try? FileHandle(forReadingFrom: fileURL) {
                    let sample = fh.readData(ofLength: 32 * 1024)
                    try? fh.close()
                    let txt = String(data: sample, encoding: .utf8) ??
                             String(data: sample, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
                    if let txt = txt, !txt.isEmpty {
                        self.previewText = txt
                        PreviewArtifactCache.shared.setText(txt, for: cacheKey)
                    }
                }
            }
        } catch {}
        isLoading = false
    }
}

/// Seamless, borderless floating hover card.
public struct HoverPreviewCardView: View {
    let entry: ArchiveEntry
    @ObservedObject var session: ArchiveBrowsingSession
    @StateObject private var model = HoverPreviewViewModel()

    public init(entry: ArchiveEntry, session: ArchiveBrowsingSession) {
        self.entry = entry
        self.session = session
    }

    private var ext: String {
        (entry.name as NSString).pathExtension.lowercased()
    }

    private var isImageFile: Bool {
        ["png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "tiff", "ico"].contains(ext)
    }

    private var isPDFFile: Bool {
        ext == "pdf"
    }

    private var isOfficeFile: Bool {
        ["docx", "xlsx", "pptx", "pages", "numbers", "key"].contains(ext)
    }

    private var isSupported: Bool {
        ArchiveHoverPreviewPanelController.isSupportedPreview(ext: ext, entry: entry)
    }

    private var isNestedArchive: Bool {
        entry.isNestedArchive
    }

    private var is3DModel: Bool {
        ["glb", "gltf", "obj", "dae", "usdz", "usd", "scn", "stl", "ply", "abc"].contains(ext)
    }

    private var isVideoFile: Bool {
        MediaPreviewExtractor.isVideo(ext: ext)
    }

    private var isAudioFile: Bool {
        MediaPreviewExtractor.isAudio(ext: ext)
    }

    private var isFramelessPreview: Bool {
        // Media files (Images, PDFs, Office documents) are frameless floating previews when enabled in preferences
        guard PureZipPreferences.shared.hoverPreviewFrameless else { return false }
        return isImageFile || isPDFFile || isOfficeFile
    }

    public var body: some View {
        Group {
            if isNestedArchive {
                nestedArchiveBody
            } else if is3DModel {
                threeDModelBody
            } else if isVideoFile {
                if let vData = model.videoData {
                    VideoHoverPreviewView(entry: entry, videoData: vData)
                } else if model.isLoading {
                    loadingPlaceholder
                        .frame(width: 460, height: 290)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                } else {
                    fallbackCard
                        .frame(width: 460, height: 290)
                }
            } else if isAudioFile {
                if let aData = model.audioData {
                    AudioHoverPreviewView(entry: entry, audioData: aData)
                } else if model.isLoading {
                    loadingPlaceholder
                        .frame(width: 440, height: 230)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                } else {
                    fallbackCard
                        .frame(width: 440, height: 230)
                }
            } else if isFramelessPreview {
                framelessBody
            } else {
                cardBody
            }
        }
        .task {
            if isSupported {
                await model.loadQuickPreview(for: entry, in: session)
            }
        }
    }

    // MARK: - 嵌套压缩包悬浮透视卡片 (Nested Archive Live Inspection HUD)
    @ViewBuilder
    private var nestedArchiveBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.orange)
                Text(entry.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if let summary = model.nestedSummary {
                    Text("\(summary.formatDisplayName) · \(summary.totalEntryCount) 项 · \(ByteCountFormatter.string(fromByteCount: summary.totalUncompressedBytes, countStyle: .file))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let summary = model.nestedSummary {
                if summary.topEntries.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Text("内部压缩包为空或受密码保护")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summary.topEntries.prefix(7)) { item in
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
                        if summary.totalEntryCount > 7 {
                            Text("... 共 \(summary.totalEntryCount) 个内部条目（双击直接进入浏览）")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        } else {
                            Spacer(minLength: 0)
                            Text("提示：双击可直接进入该嵌套压缩包浏览")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if model.isLoading {
                loadingPlaceholder
            } else {
                fallbackCard
            }
        }
        .padding(14)
        .frame(width: 440, height: 270)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
    }

    // MARK: - 3D 模型悬浮实时渲染窗口 (GLB / GLTF 3D Model HUD)
    @ViewBuilder
    private var threeDModelBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                    Text(entry.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            if let url = model.model3DURL {
                Model3DPreviewView(fileURL: url)
                    .frame(maxWidth: .infinity, maxHeight: 310)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
            } else if model.isLoading {
                loadingPlaceholder
            } else {
                fallbackCard
            }
        }
        .padding(14)
        .frame(width: 460, height: 380)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
    }

    // MARK: - 无外框纯内容悬浮预览 (Direct Content Floating HUD)
    @ViewBuilder
    private var framelessBody: some View {
        Group {
            if isImageFile {
                if let img = model.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 5)
                        .padding(8)
                } else if model.isLoading {
                    loadingPlaceholder
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
                } else {
                    fallbackCard
                }
            } else if isPDFFile {
                if !model.pdfPages.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(0..<model.pdfPages.count, id: \.self) { idx in
                            Image(nsImage: model.pdfPages[idx])
                                .resizable()
                                .scaledToFit()
                                .background(Color.white)
                                .cornerRadius(4)
                                .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 5)
                        }
                    }
                    .padding(8)
                } else if model.isLoading {
                    loadingPlaceholder
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
                } else {
                    fallbackCard
                }
            } else if isOfficeFile {
                if let thumb = model.quickLookThumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 5)
                        .padding(8)
                } else if model.isLoading {
                    loadingPlaceholder
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
                } else {
                    fallbackCard
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - 经典带外框卡片预览
    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Filename in subtle secondary text (Adaptive across Dark & Light)
            HStack(alignment: .center) {
                Text(entry.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if isImageFile, let dims = model.imageDimensions {
                    Text("\(Int(dims.width)) × \(Int(dims.height)) · \(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if !isImageFile {
                    Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            // Body Content Area (Borderless floating preview)
            Group {
                if isImageFile {
                    if let img = model.previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 260)
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
                    } else if model.isLoading {
                        loadingPlaceholder
                    } else {
                        fallbackCard
                    }
                } else if isPDFFile {
                    if !model.pdfPages.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(0..<model.pdfPages.count, id: \.self) { idx in
                                Image(nsImage: model.pdfPages[idx])
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 255)
                                    .background(Color.white)
                                    .cornerRadius(4)
                                    .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 255, alignment: .center)
                    } else if model.isLoading {
                        loadingPlaceholder
                    } else {
                        fallbackCard
                    }
                } else if isOfficeFile && model.quickLookThumbnail != nil {
                    if let thumb = model.quickLookThumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 260)
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
                    }
                } else {
                    // Text / Markdown / Code / JSON / Fallback
                    if let text = model.previewText, !text.isEmpty {
                        MarkdownTextPreviewView(text: text)
                    } else if model.isLoading {
                        loadingPlaceholder
                    } else {
                        fallbackCard
                    }
                }
            }
        }
        .padding(14)
        .frame(width: (isImageFile || isPDFFile) ? 420 : 440, height: isImageFile ? 320 : (isPDFFile ? 310 : 330))
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
    }

    private var fallbackCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
            Text(entry.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在生成高清预览...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rich Markdown & formatted text preview view.
public struct MarkdownTextPreviewView: View {
    let text: String

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(text.components(separatedBy: .newlines).prefix(80).enumerated()), id: \.offset) { _, line in
                    formatLine(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func formatLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("# ") {
            Text(trimmed.dropFirst(2))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 5)
                .padding(.bottom, 2)
        } else if trimmed.hasPrefix("## ") {
            Text(trimmed.dropFirst(3))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 4)
                .padding(.bottom, 1)
        } else if trimmed.hasPrefix("### ") {
            Text(trimmed.dropFirst(4))
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 2)
        } else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
            if trimmed.contains("---") {
                Divider().opacity(0.3)
            } else {
                let columns = trimmed.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
                        if let attr = try? AttributedString(markdown: col) {
                            Text(attr)
                                .font(.system(size: 10.5, weight: idx == 0 ? .medium : .regular))
                                .foregroundStyle(idx == 0 ? .primary : .secondary)
                                .lineLimit(2)
                        } else {
                            Text(col)
                                .font(.system(size: 10.5, weight: idx == 0 ? .medium : .regular))
                                .foregroundStyle(idx == 0 ? .primary : .secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 3)
        } else {
            if let attr = try? AttributedString(markdown: line) {
                Text(attr)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineSpacing(2.5)
            } else {
                Text(line)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineSpacing(2.5)
            }
        }
    }
}

/// High-Resolution Vector Renderer for PDF Pages (Retina-ready)
public func renderHighResolutionPDFPage(_ page: PDFPage, targetWidth: CGFloat = 1200) -> NSImage {
    let pageBounds = page.bounds(for: .mediaBox)
    guard pageBounds.width > 0, pageBounds.height > 0 else {
        return page.thumbnail(of: NSSize(width: targetWidth, height: targetWidth), for: .mediaBox)
    }

    let scale = max(1.0, targetWidth / pageBounds.width)
    let pixelWidth = max(1, Int(pageBounds.width * scale))
    let pixelHeight = max(1, Int(pageBounds.height * scale))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return page.thumbnail(of: NSSize(width: targetWidth, height: targetWidth * (pageBounds.height / pageBounds.width)), for: .mediaBox)
    }

    // Fill clean white background
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

    // Scale context to high resolution
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()

    guard let cgImage = context.makeImage() else {
        return page.thumbnail(of: NSSize(width: targetWidth, height: targetWidth * (pageBounds.height / pageBounds.width)), for: .mediaBox)
    }

    let image = NSImage(cgImage: cgImage, size: NSSize(width: pageBounds.width, height: pageBounds.height))
    return image
}

// MARK: - Unified 3D Model Preview (GLB/GLTF via WebKit + OBJ/DAE/USDZ/STL via SceneKit)
public struct Model3DPreviewView: View {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private var ext: String {
        fileURL.pathExtension.lowercased()
    }

    public var body: some View {
        if ["glb", "gltf"].contains(ext) {
            GLBModel3DView(fileURL: fileURL)
        } else {
            SceneKitModel3DView(fileURL: fileURL)
        }
    }
}

public struct SceneKitModel3DView: NSViewRepresentable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        loadScene(in: scnView)
        return scnView
    }

    public func updateNSView(_ nsView: SCNView, context: Context) {
        if context.coordinator.lastURL != fileURL {
            context.coordinator.lastURL = fileURL
            loadScene(in: nsView)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        var lastURL: URL?
    }

    private func loadScene(in scnView: SCNView) {
        var loadedScene: SCNScene? = try? SCNScene(url: fileURL, options: nil)
        if loadedScene == nil, let data = try? Data(contentsOf: fileURL) {
            let source = SCNSceneSource(data: data, options: nil)
            loadedScene = source?.scene(options: nil)
        }
        guard let scene = loadedScene else {
            scnView.scene = nil
            return
        }

        // Apply default clean clay material to geometry elements that have no texture/material
        scene.rootNode.enumerateChildNodes { node, _ in
            if let geom = node.geometry {
                for mat in geom.materials {
                    mat.lightingModel = .physicallyBased
                    if mat.diffuse.contents == nil {
                        mat.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.82, alpha: 1.0)
                    }
                }
            }
        }

        // Continuous gentle rotation around Y axis matching GLBModel3DView
        let container = SCNNode()
        for child in scene.rootNode.childNodes {
            container.addChildNode(child)
        }
        scene.rootNode.addChildNode(container)
        let rotate = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 14.0))
        container.runAction(rotate)

        scnView.scene = scene
    }
}

// MARK: - 3D GLB/GLTF Model Viewer (WebKit + Google <model-viewer>)
public struct GLBModel3DView: NSViewRepresentable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // transparent background
        loadModel(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastURL != fileURL {
            context.coordinator.lastURL = fileURL
            loadModel(in: nsView)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator {
        var parent: GLBModel3DView
        var lastURL: URL?
        init(_ parent: GLBModel3DView) {
            self.parent = parent
        }
    }

    private func loadModel(in webView: WKWebView) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let base64 = data.base64EncodedString()
        let isGLTF = fileURL.pathExtension.lowercased() == "gltf"
        let mime = isGLTF ? "model/gltf+json" : "model/gltf-binary"
        let dataURI = "data:\(mime);base64,\(base64)"

        // Check bundled model-viewer.js or fallback to offline cache/CDN
        var scriptTag = ""
        if let scriptURL = Bundle.main.url(forResource: "model-viewer.min", withExtension: "js") ?? Bundle.main.url(forResource: "model-viewer", withExtension: "js"),
           let jsContent = try? String(contentsOf: scriptURL, encoding: .utf8) {
            scriptTag = "<script type=\"module\">\(jsContent)</script>"
        } else if let localScript = try? String(contentsOf: URL(fileURLWithPath: "/Users/minato/Desktop/PureZip/Resources/model-viewer.min.js"), encoding: .utf8) {
            scriptTag = "<script type=\"module\">\(localScript)</script>"
        } else {
            scriptTag = "<script type=\"module\" src=\"https://ajax.googleapis.com/ajax/libs/model-viewer/3.5.0/model-viewer.min.js\"></script>"
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
          model-viewer {
            width: 100%;
            height: 100%;
            background-color: transparent;
            --poster-color: transparent;
          }
        </style>
        \(scriptTag)
        </head>
        <body>
          <model-viewer
            src="\(dataURI)"
            auto-rotate
            rotation-per-second="25deg"
            camera-controls
            shadow-intensity="1"
            exposure="1.0"
            interaction-prompt="none">
          </model-viewer>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Video Hover Skimmer Preview (5 Keyframes Flashing with Seamless Loop)

public struct VideoHoverPreviewView: View {
    let entry: ArchiveEntry
    let videoData: VideoPreviewData
    @State private var currentFrameIndex: Int = 0
    @State private var timerTask: Task<Void, Never>? = nil

    public init(entry: ArchiveEntry, videoData: VideoPreviewData) {
        self.entry = entry
        self.videoData = videoData
    }

    public var body: some View {
        ZStack {
            Color.black

            if !videoData.keyframes.isEmpty {
                let frame = videoData.keyframes[min(currentFrameIndex, videoData.keyframes.count - 1)]
                Image(nsImage: frame)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentFrameIndex)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("无法提取视频预览帧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Top gradient overlay with filename
            VStack {
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                    Text(entry.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.75), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Spacer()

                // Bottom floating info capsule
                HStack(spacing: 8) {
                    // Frame indicator dots
                    if videoData.keyframes.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(0..<videoData.keyframes.count, id: \.self) { idx in
                                Circle()
                                    .fill(idx == currentFrameIndex ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color.white.opacity(0.4))
                                    .frame(width: idx == currentFrameIndex ? 6 : 4, height: idx == currentFrameIndex ? 6 : 4)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // Codec + Resolution + Duration
                    HStack(spacing: 5) {
                        if !videoData.codecName.isEmpty {
                            Text(videoData.codecName)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.18))
                                .cornerRadius(4)
                        }
                        if !videoData.resolutionFormatted.isEmpty {
                            Text(videoData.resolutionFormatted)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.75))
                                .cornerRadius(4)
                        }
                        Text(videoData.durationFormatted)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(4)
                    }
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 16)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(width: 460, height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 14, y: 6)
        .onAppear {
            startLoop()
        }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    private func startLoop() {
        guard videoData.keyframes.count > 1 else { return }
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.15)) {
                    if currentFrameIndex < videoData.keyframes.count - 1 {
                        currentFrameIndex += 1
                    } else {
                        currentFrameIndex = 0
                    }
                }
                // Pause slightly longer at end of cycle
                if currentFrameIndex == 0 {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                }
            }
        }
    }
}

// MARK: - Audio Hover Preview (Panoramic Waveform when no artwork)

public struct AudioHoverPreviewView: View {
    let entry: ArchiveEntry
    let audioData: AudioPreviewData
    @Environment(\.colorScheme) private var colorScheme

    public init(entry: ArchiveEntry, audioData: AudioPreviewData) {
        self.entry = entry
        self.audioData = audioData
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let artwork = audioData.artwork {
                // Case A: Has embedded cover artwork
                HStack(spacing: 14) {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(audioData.title ?? entry.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let artist = audioData.artist {
                            Text(artist + (audioData.album.map { " · \($0)" } ?? ""))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            Text(audioData.specBadge)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.18))
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                                .clipShape(Capsule())

                            Text(audioData.durationFormatted)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // Case B: No cover artwork -> Waveform is the centerpiece
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))

                    Text(audioData.title ?? entry.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(audioData.specBadge)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.18))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                        .clipShape(Capsule())

                    Text(audioData.durationFormatted)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Panoramic Waveform Display
            AcousticWaveformBarsView(
                samples: audioData.waveformSamples,
                progress: 0.0,
                barHeight: audioData.artwork != nil ? 34 : 54,
                gradientColors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.03, green: 0.40, blue: 0.90)]
            )

            // Lyrics preview if present (2 lines of lyrics in subtle italic style)
            if let lyrics = audioData.lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let sampleLyrics = lyrics.split(separator: "\n").prefix(2).joined(separator: " / ")
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(sampleLyrics)
                        .font(.system(size: 11, weight: .regular))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "quote.closing")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .frame(width: 440)
        .background(
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                .overlay(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.4))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 14, y: 5)
    }
}
