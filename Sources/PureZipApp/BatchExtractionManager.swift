import AppKit
import SwiftUI
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

/// Manages multi-archive batch extraction queues and execution.
@MainActor
public final class BatchExtractionManager: ObservableObject {
    public static let shared = BatchExtractionManager()

    public final class Item: Identifiable, ObservableObject {
        public let id = UUID()
        public let sourceURL: URL
        public let primaryURL: URL
        public let isSplit: Bool
        public let splitCount: Int
        public let fileSize: Int64
        @Published public var status: Status = .pending
        @Published public var progress: Double = 0.0
        @Published public var password: String? = nil
        @Published public var destinationFolder: URL? = nil
        @Published public var errorMessage: String? = nil

        public enum Status: Equatable {
            case pending
            case extracting
            case completed
            case failed
            case needsPassword
        }

        public init(url: URL) {
            self.sourceURL = url
            self.primaryURL = ArchiveVolumeFamily.primaryURL(for: url)
            self.isSplit = ArchiveVolumeFamily.isSplitArchive(at: url)
            self.splitCount = ArchiveVolumeFamily.memberURLs(for: url).count
            let attrs = try? FileManager.default.attributesOfItem(atPath: primaryURL.path)
            self.fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    @Published public var isShowingSheet: Bool = false
    @Published public var items: [Item] = []
    @Published public var isExtracting: Bool = false
    @Published public var extractToSubfolder: Bool = true
    @Published public var overallProgress: Double = 0.0
    @Published public var completedCount: Int = 0
    @Published public var activePasswordItem: Item? = nil

    private let broker = ArchiveEngineBroker()

    public init() {}

    public func startBatch(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // Deduplicate primary URLs (especially for split archives like .001, .002)
        var seen = Set<URL>()
        var queue: [Item] = []

        for raw in urls {
            let primary = ArchiveVolumeFamily.primaryURL(for: raw)
            if !seen.contains(primary) && FileManager.default.fileExists(atPath: primary.path) {
                seen.insert(primary)
                queue.append(Item(url: primary))
            }
        }

        guard !queue.isEmpty else { return }

        self.items = queue
        self.completedCount = 0
        self.overallProgress = 0.0
        self.isShowingSheet = true
        self.isExtracting = false
    }

    public func runBatchExtraction() {
        guard !isExtracting else { return }
        isExtracting = true
        completedCount = 0
        overallProgress = 0.0

        Task {
            let total = Double(items.count)
            for (idx, item) in items.enumerated() {
                if item.status == .completed { continue }
                item.status = .extracting
                item.progress = 0.0
                item.errorMessage = nil

                let parentDir = item.primaryURL.deletingLastPathComponent()
                let (stem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(item.primaryURL.lastPathComponent)
                let targetDir = extractToSubfolder
                    ? parentDir.appendingPathComponent(stem)
                    : parentDir

                do {
                    try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                    let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "batch-extract")
                    defer { stageLease.release() }

                    try await broker.extract(
                        item.primaryURL,
                        entries: [],
                        to: stageLease.url,
                        password: item.password
                    ) { [weak item] prog in
                        Task { @MainActor in
                            if let total = prog.total, total > 0 {
                                item?.progress = Double(prog.completed) / Double(total)
                            }
                        }
                    }

                    let excludeAux = PureZipPreferences.shared.autoExcludeSystemAuxiliary
                    let manifest = try ExtractionFinalizationManifest.prepare(
                        stagingDirectory: stageLease.url,
                        shouldRemove: excludeAux ? nil : { _ in false }
                    )
                    var collisionIndex = DestinationCollisionIndex()
                    _ = try FinderExtractionPublisher.publishMergingContents(
                        using: manifest,
                        to: targetDir,
                        collisionIndex: &collisionIndex,
                        directoryConflictPolicy: .rename
                    )

                    item.destinationFolder = targetDir
                    item.status = .completed
                    item.progress = 1.0
                    completedCount += 1
                } catch {
                    let errStr = error.localizedDescription.lowercased()
                    if let engErr = error as? ArchiveEngineError, engErr == .wrongPassword || errStr.contains("password") {
                        item.status = .needsPassword
                        item.errorMessage = "需要解压密码"
                        activePasswordItem = item
                    } else {
                        item.status = .failed
                        item.errorMessage = error.localizedDescription
                    }
                }

                overallProgress = Double(idx + 1) / total
            }
            isExtracting = false
        }
    }

    public func retryItemWithPassword(_ item: Item, password: String) {
        item.password = password
        activePasswordItem = nil
        item.status = .pending
        runBatchExtraction()
    }

    public func revealAllInFinder() {
        let dests = items.compactMap(\.destinationFolder)
        if !dests.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(dests)
        }
    }
}

/// Sheet UI for multi-archive batch extraction.
public struct BatchExtractionSheetView: View {
    @ObservedObject var manager = BatchExtractionManager.shared
    @State private var passwordInput: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("批量解压")
                        .font(.headline)
                    Text("共 \(manager.items.count) 个压缩包待处理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("解压到各自同名文件夹", isOn: $manager.extractToSubfolder)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .disabled(manager.isExtracting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // List of Archives
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(manager.items) { item in
                        BatchItemRow(item: item)
                    }
                }
                .padding(16)
            }
            .frame(height: 280)

            Divider()

            // Overall Progress & Actions
            VStack(spacing: 12) {
                if manager.isExtracting {
                    VStack(spacing: 4) {
                        ProgressView(value: manager.overallProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        HStack {
                            Text("正在处理第 \(manager.completedCount + 1) / \(manager.items.count) 个...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(manager.overallProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button("关闭") {
                        manager.isShowingSheet = false
                    }
                    .disabled(manager.isExtracting)

                    Spacer()

                    if manager.completedCount == manager.items.count && !manager.items.isEmpty {
                        Button("在访达中显示全部") {
                            manager.revealAllInFinder()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(manager.isExtracting ? "正在解压..." : "开始批量解压") {
                            manager.runBatchExtraction()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.isExtracting)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 540)
        .sheet(item: $manager.activePasswordItem) { item in
            VStack(spacing: 14) {
                Text("输入「\(item.primaryURL.lastPathComponent)」的解压密码")
                    .font(.headline)

                SecureField("密码", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("取消") {
                        manager.activePasswordItem = nil
                    }
                    Spacer()
                    Button("解锁并继续") {
                        let pwd = passwordInput
                        passwordInput = ""
                        manager.retryItemWithPassword(item, password: pwd)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(passwordInput.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }
}

private struct BatchItemRow: View {
    @ObservedObject var item: BatchExtractionManager.Item

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 24))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.primaryURL.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if item.isSplit {
                        Text("\(item.splitCount) 分卷")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let err = item.errorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            switch item.status {
            case .pending:
                Text("就绪")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .extracting:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .needsPassword:
                Button("输入密码") {
                    BatchExtractionManager.shared.activePasswordItem = item
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
