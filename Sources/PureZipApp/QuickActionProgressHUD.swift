import AppKit
import SwiftUI

/// Floating HUD window showing background operation progress for Finder Quick Actions (ZIP, Compress to, Extract to, etc.)
@MainActor
public final class QuickActionProgressHUD: ObservableObject {
    public static let shared = QuickActionProgressHUD()

    @Published public var title: String = ""
    @Published public var subtitle: String = ""
    @Published public var progress: Double = 0.0
    @Published public var isIndeterminate: Bool = true
    @Published public var isCompleted: Bool = false
    @Published public var systemSymbol: String = "archivebox"

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var showDelayedTask: Task<Void, Never>?
    private var onCancel: (() -> Void)?

    private init() {}

    private func ensurePanel() -> NSPanel {
        if let existing = panel { return existing }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 74),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: QuickActionProgressHUDView(hud: self))
        p.contentView = hostingView
        self.panel = p
        return p
    }

    public func show(
        title: String,
        symbol: String = "archivebox",
        delay: TimeInterval = 0.35,
        cancelAction: (() -> Void)? = nil
    ) {
        dismissTask?.cancel()
        dismissTask = nil
        showDelayedTask?.cancel()

        self.title = title
        self.subtitle = "正在处理中..."
        self.progress = 0.0
        self.isIndeterminate = true
        self.isCompleted = false
        self.systemSymbol = symbol
        self.onCancel = cancelAction

        showDelayedTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
            }
            let p = self.ensurePanel()
            if let screen = NSScreen.main {
                let margin: CGFloat = 28
                let originX = screen.visibleFrame.maxX - 330 - margin
                let originY = screen.visibleFrame.minY + margin
                p.setFrameOrigin(NSPoint(x: originX, y: originY))
            }
            p.alphaValue = 0
            p.orderFront(nil)
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 1.0
            }
        }
    }

    public func update(progress: Double, subtitle: String? = nil) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.isIndeterminate = false
        if let sub = subtitle {
            self.subtitle = sub
        } else {
            self.subtitle = String(format: "已完成 %d%%", Int(self.progress * 100))
        }
    }

    public func finish(message: String = "完成") {
        showDelayedTask?.cancel()
        showDelayedTask = nil

        guard let p = panel, p.isVisible else {
            return
        }

        self.isCompleted = true
        self.subtitle = message
        self.progress = 1.0

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                p.animator().alphaValue = 0
            }
            p.orderOut(nil)
        }
    }

    public func cancel() {
        showDelayedTask?.cancel()
        showDelayedTask = nil
        onCancel?()
        panel?.orderOut(nil)
    }
}

public struct QuickActionProgressHUDView: View {
    @ObservedObject var hud: QuickActionProgressHUD

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(hud.isCompleted ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.15))
                    .frame(width: 38, height: 38)

                Image(systemName: hud.isCompleted ? "checkmark" : hud.systemSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(hud.isCompleted ? .green : .accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(hud.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if hud.isIndeterminate && !hud.isCompleted {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    ProgressView(value: hud.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(hud.isCompleted ? .green : .accentColor)
                }

                Text(hud.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if !hud.isCompleted {
                Button(action: { hud.cancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
        .frame(width: 330, height: 74)
    }
}
