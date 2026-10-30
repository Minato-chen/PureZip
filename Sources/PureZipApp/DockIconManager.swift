import AppKit
import Foundation
import ArchiveCore

/// Coordinates dynamically switching between NSApplication.ActivationPolicy .regular and .accessory
/// based on the user's preference ("always", "never", "activeWindows").
@MainActor
public final class DockIconManager {
    public static let shared = DockIconManager()

    private var debounceWorkItem: DispatchWorkItem?

    private init() {
        // Observe preference changes
        NotificationCenter.default.addObserver(
            forName: Notification.Name("PureZipDockIconVisibilityModeChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePolicy()
            }
        }

        // Observe window notifications to detect when visible regular windows open/close
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEvaluation()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEvaluation()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEvaluation()
            }
        }
    }

    /// Evaluates whether any regular, interactive window (Main window, Settings, etc.) is currently visible on screen.
    public var hasVisibleInteractiveWindows: Bool {
        NSApp.windows.contains { window in
            // Exclude non-interactive panels like hover previews, status item popup windows, or hidden windows
            guard !(window is NSPanel), window.isVisible, !window.isMiniaturized else {
                return false
            }
            // Ignore system auxiliary/offscreen windows or windows with 0 area
            let frame = window.frame
            return frame.width > 100 && frame.height > 100
        }
    }

    /// Schedule an evaluation with a slight debounce to avoid flickering when windows change
    public func scheduleEvaluation() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluatePolicy()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    /// Applies the appropriate activation policy based on the current mode and window state
    public func evaluatePolicy() {
        let mode = PureZipPreferences.shared.dockIconVisibilityMode

        switch mode {
        case "always":
            setPolicy(.regular)
        case "activeWindows":
            if hasVisibleInteractiveWindows {
                setPolicy(.regular)
            } else {
                setPolicy(.accessory)
            }
        case "never":
            fallthrough
        default:
            setPolicy(.accessory)
        }
    }

    private func setPolicy(_ targetPolicy: NSApplication.ActivationPolicy) {
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
            if targetPolicy == .regular {
                NSApp.unhideWithoutActivation()
            }
        }
    }
}
