import AppKit
import SwiftUI
import ArchiveCore

/// Manages a native standalone, movable Settings window on macOS,
/// replacing modal attached sheets so the user can drag it around freely.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show(session: ArchiveBrowsingSession) {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            PureZipPreferences.shared.syncAppearance()
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "PureZip 偏好设置"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let hostingView = NSHostingView(rootView: SettingsView(session: session))
        win.contentView = hostingView
        self.window = win
        PureZipPreferences.shared.syncAppearance()

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        // Kept in memory for instant re-opening
    }
}
