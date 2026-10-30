import AppKit
import QuickLookUI
import ArchiveCore
import ArchiveEngines

/// Coordinates native macOS QuickLook preview panel (`QLPreviewPanel`) for Spacebar preview.
@MainActor
public final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookPreviewController()

    public private(set) var currentPreviewURL: URL?
    public private(set) var currentEntry: ArchiveEntry?
    private var activeLease: ManagedWorkFileLease?

    private override init() {
        super.init()
    }

    /// Toggles the native macOS QuickLook HUD panel for the given entry or closes it if already open for this entry.
    public func togglePreview(for entry: ArchiveEntry?, session: ArchiveBrowsingSession) {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.isVisible {
            if let entry, currentEntry?.id == entry.id {
                // Same entry: close panel
                panel.orderOut(nil)
                return
            }
        }

        guard let entry, entry.type != .directory else {
            closePreview()
            return
        }

        Task {
            await prepareAndShow(entry: entry, session: session)
        }
    }

    /// Extracts the entry to temporary staging cache and presents the native `QLPreviewPanel`.
    public func prepareAndShow(entry: ArchiveEntry, session: ArchiveBrowsingSession) async {
        guard let archiveURL = session.currentArchiveURL, entry.type != .directory else { return }

        session.isBusy = true
        session.statusMessage = "正在准备「\(entry.name)」的系统快速预览..."

        do {
            let fileURL = try await PreviewArtifactCache.shared.sharedExtractedFile(
                for: entry,
                in: archiveURL,
                broker: session.broker
            )

            self.currentPreviewURL = fileURL
            self.currentEntry = entry
            session.quickLookItemURL = fileURL
            session.statusMessage = "已展开原生系统预览: \(entry.name)"

            if let panel = QLPreviewPanel.shared() {
                panel.dataSource = self
                panel.delegate = self
                panel.reloadData()
                panel.makeKeyAndOrderFront(nil)
            }
        } catch {
            session.statusMessage = "系统预览提取失败: \(error.localizedDescription)"
        }

        session.isBusy = false
    }

    /// Dynamically switches the previewed item if the QuickLook HUD panel is already visible (like Finder arrow navigation).
    public func updatePreviewIfVisible(for entry: ArchiveEntry?, session: ArchiveBrowsingSession) {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible else {
            return
        }
        guard let entry, entry.type != .directory else { return }
        guard currentEntry?.id != entry.id else { return }

        Task {
            await prepareAndShow(entry: entry, session: session)
        }
    }

    /// Closes the QuickLook HUD panel and cleans up the staging lease.
    public func closePreview() {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared() {
            panel.orderOut(nil)
        }
        activeLease?.release()
        activeLease = nil
        currentPreviewURL = nil
        currentEntry = nil
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            currentPreviewURL != nil ? 1 : 0
        }
    }

    nonisolated public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            currentPreviewURL as NSURL?
        }
    }

    // MARK: - QLPreviewPanelDelegate

    nonisolated public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Spacebar inside QuickLook closes the panel
        if event.type == .keyDown && event.keyCode == 49 {
            DispatchQueue.main.async {
                panel.orderOut(nil)
            }
            return true
        }
        return false
    }
}
