import AppKit
import SwiftUI
import Quartz
import QuickLookUI
import ArchiveCore
import ArchiveEngines

struct QuickLookArchiveView: View {
    let archiveName: String
    let descriptor: ArchiveFormatDescriptor
    let entries: [ArchiveEntry]
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archiveName)
                        .font(.headline)
                    Text("\(descriptor.displayName) • 共 \(totalCount) 项 • Tier: \(descriptor.tier.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.type == .directory ? "folder.fill" : "doc.text")
                        .foregroundStyle(entry.type == .directory ? .blue : .secondary)
                    Text(entry.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if entry.type != .directory {
                        Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

/// Quick Look preview controller (`QLPreviewingController`) for archive files.
@objc(PreviewViewController)
public final class PreviewViewController: NSViewController, QLPreviewingController {
    private let broker = ArchiveEngineBroker()
    private let seedStore = ArchivePreviewSeedStore()

    public override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
    }

    public func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        Task { @MainActor in
            do {
                let desc = try await broker.descriptor(for: url)
                let index = try EntryIndex()
                defer { index.close() }

                var allEntries: [ArchiveEntry] = []
                let stream = try await broker.list(url)
                for try await batch in stream {
                    allEntries.append(contentsOf: batch)
                    try index.insert(batch)
                }

                // Publish preview seed so main app can claim it with zero latency
                if ArchivePreviewSeedPolicy.supports(desc.format),
                   let fp = try? ArchiveSourceFingerprint.capture(at: ArchiveVolumeFamily.primaryURL(for: url)) {
                    _ = try? await seedStore.publish(
                        fingerprint: fp,
                        format: desc.format,
                        entries: allEntries,
                        isAuthoritativeForAppListing: true
                    )
                }

                let visibleRoot = try index.children(of: "", limit: 300, includeAuxiliary: false)
                let totalCount = try index.count()
                let hosting = NSHostingView(
                    rootView: QuickLookArchiveView(
                        archiveName: url.lastPathComponent,
                        descriptor: desc,
                        entries: visibleRoot,
                        totalCount: totalCount
                    )
                )
                hosting.frame = self.view.bounds
                hosting.autoresizingMask = [.width, .height]
                self.view.subviews.forEach { $0.removeFromSuperview() }
                self.view.addSubview(hosting)
                handler(nil)
            } catch {
                handler(error)
            }
        }
    }
}

@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

@main
struct PureZipQuickLookMain {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            print("PureZipQuickLook extension binary ready (principal class: PureZipQuickLook.PreviewViewController)")
            return
        }
        _ = NSExtensionMain()
    }
}
