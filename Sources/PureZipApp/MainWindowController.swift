import AppKit
import SwiftUI
import ArchiveCore

/// Native window controller managing the lifecycle of the PureZip main application window.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    public static let shared = MainWindowController()

    public private(set) var window: NSWindow?
    private var session: ArchiveBrowsingSession?

    private override init() {
        super.init()
    }

    /// Attaches the SwiftUI-created window instance so it is intercepted and never demolished.
    public func attach(window: NSWindow, session: ArchiveBrowsingSession) {
        // If an existing primary window is already tracked and alive, reuse it
        if let existing = self.window, existing != window {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
            }
            return
        }

        self.window = window
        self.session = session
        window.delegate = self
        window.isReleasedWhenClosed = false
        session.mainWindow = window
        PureZipPreferences.shared.syncAppearance()
        session.updateWindowFloatingLevel()
    }

    /// Presents and focuses the PureZip main window, ensuring it is never dismantled or lost.
    public func show(session: ArchiveBrowsingSession) {
        self.session = session
        NSApp.unhideWithoutActivation()
        NSApp.activate(ignoringOtherApps: true)

        let targetWindow = window ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain })
        if let existing = targetWindow {
            self.window = existing
            session.mainWindow = existing

            if !existing.isVisible {
                existing.center()
            }
            session.updateWindowFloatingLevel()
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        // If a window is currently being created or displayed, do not spawn another
        if let firstWin = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            self.window = firstWin
            session.mainWindow = firstWin
            firstWin.makeKeyAndOrderFront(nil)
            firstWin.orderFrontRegardless()
            return
        }

        let rootView = RootApplicationView(session: session)
        let hosting = NSHostingView(rootView: rootView)

        let initialSize: NSSize
        let minSize: NSSize
        if session.currentArchiveURL == nil {
            initialSize = NSSize(width: 440, height: 480)
            minSize = NSSize(width: 380, height: 380)
        } else if session.currentDescriptor?.format == .dmg {
            if session.isDMGCapsuleExpanded {
                initialSize = NSSize(width: 680, height: 500)
                minSize = NSSize(width: 440, height: 380)
            } else {
                initialSize = NSSize(width: 420, height: 440)
                minSize = NSSize(width: 360, height: 340)
            }
        } else if session.windowMode == .capsuleFloating {
            initialSize = NSSize(width: 420, height: 440)
            minSize = NSSize(width: 360, height: 340)
        } else {
            initialSize = NSSize(width: 1080, height: 680)
            minSize = NSSize(width: 860, height: 560)
        }

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.contentView = hosting
        win.minSize = minSize
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        self.window = win
        session.mainWindow = win

        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of destroying, keeping state completely intact for instant reopen
        sender.orderOut(nil)
        return false
    }

    public func windowWillClose(_ notification: Notification) {
        // Extra safeguard
    }
}
