import AppKit
import SwiftUI
import Combine
import ArchiveCore

/// Manages the native macOS Menu Bar Status Item for PureZip PureShelf,
/// supporting left-click popover presentation and right-click native contextual menu with "退出 PureZip".
@MainActor
public final class PureZipStatusItemController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    public static var shared: PureZipStatusItemController?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let session: ArchiveBrowsingSession
    private var cancellables = Set<AnyCancellable>()
    private var isManuallyClosing = false
    private var lastCloseTime: TimeInterval = 0

    public init(session: ArchiveBrowsingSession) {
        self.session = session
        super.init()
        Self.shared = self
        setupController()
    }

    public func closePopover() {
        isManuallyClosing = true
        lastCloseTime = ProcessInfo.processInfo.systemUptime
        popover?.close()
        isManuallyClosing = false
        statusItem?.button?.isHighlighted = false
        statusItem?.button?.highlight(false)
    }

    public func setPinned(_ isPinned: Bool) {
        PureZipPreferences.shared.pureShelfKeepWindowPinned = isPinned
        applyPinningState()
    }

    public func applyPinningState() {
        guard let popover = popover else { return }
        let isPinned = PureZipPreferences.shared.pureShelfKeepWindowPinned
        popover.behavior = isPinned ? .applicationDefined : .transient

        guard let window = popover.contentViewController?.view.window else { return }
        if isPinned {
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = false
                panel.isFloatingPanel = true
            }
        } else {
            window.level = .floating
            window.collectionBehavior = [.transient]
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = true
            }
        }
    }

    private func setupController() {
        // Observe enablePureShelf preference
        PureZipPreferences.shared.$enablePureShelf
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.ensureStatusItemCreated()
                } else {
                    self?.removeStatusItem()
                }
            }
            .store(in: &cancellables)

        if PureZipPreferences.shared.enablePureShelf {
            ensureStatusItemCreated()
        }

        // Observe shelf count to update badge
        session.$shelfItems
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.updateBadge(count: items.count)
            }
            .store(in: &cancellables)

        // Observe pureShelfKeepWindowPinned preference
        PureZipPreferences.shared.$pureShelfKeepWindowPinned
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyPinningState()
            }
            .store(in: &cancellables)

        // Observe appearanceMode preference to dynamically sync popover appearance
        PureZipPreferences.shared.$appearanceMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncPopoverAppearance()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSNotification.Name("PureZipAppearanceDidChange"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.syncPopoverAppearance()
            }
        }
    }

    public func syncPopoverAppearance() {
        let appearance = PureZipPreferences.shared.effectiveNSAppearance
        popover?.appearance = appearance
        if let window = popover?.contentViewController?.view.window {
            window.appearance = appearance
        }
    }

    private func ensureStatusItemCreated() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = PureZipIcons.menuBarArchIcon
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // .leftMouseDown ensures instantaneous popover toggle without dropped clicks or drag cancelation;
            // .rightMouseUp prevents the macOS AppKit status item button highlight freeze bug.
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            button.toolTip = "Pure Shelf（左键打开，右键显示菜单）"
        }
        self.statusItem = item

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 350, height: 350)
        popover.behavior = PureZipPreferences.shared.pureShelfKeepWindowPinned ? .applicationDefined : .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarShelfView(session: session))
        self.popover = popover
        syncPopoverAppearance()

        updateBadge(count: session.shelfItems.count)
    }

    // MARK: - NSPopoverDelegate

    public func popoverWillShow(_ notification: Notification) {
        syncPopoverAppearance()
    }

    public func popoverDidShow(_ notification: Notification) {
        applyPinningState()
        syncPopoverAppearance()
    }

    public func popoverWillClose(_ notification: Notification) {
        lastCloseTime = ProcessInfo.processInfo.systemUptime
    }

    public func popoverDidClose(_ notification: Notification) {
        lastCloseTime = ProcessInfo.processInfo.systemUptime
        statusItem?.button?.isHighlighted = false
        statusItem?.button?.highlight(false)
    }

    public func popoverShouldClose(_ popover: NSPopover) -> Bool {
        if isManuallyClosing { return true }
        if PureZipPreferences.shared.pureShelfKeepWindowPinned {
            return false
        }
        return true
    }

    private func removeStatusItem() {
        if let popover = popover, popover.isShown {
            popover.close()
        }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            self.statusItem = nil
        }
    }

    private func updateBadge(count: Int) {
        guard let button = statusItem?.button else { return }
        if PureZipPreferences.shared.pureShelfShowCountBadge && count > 0 {
            button.title = " \(count)"
            button.font = .systemFont(ofSize: 10, weight: .bold)
        } else {
            button.title = ""
        }
    }

    // MARK: - Click Handling (Left: Popover / Right: Context Menu with Quit)

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let currentEvent = NSApp.currentEvent
        let isRightClick = currentEvent?.type == .rightMouseUp ||
                           currentEvent?.type == .rightMouseDown ||
                           (currentEvent?.modifierFlags.contains(.control) == true)

        if isRightClick {
            if let popover = popover, popover.isShown {
                closePopover()
            }
            showContextMenu(sender: sender)
        } else {
            togglePopover(sender: sender)
        }
    }

    public func togglePopover(sender: NSStatusBarButton) {
        guard let popover = popover else { return }
        let now = ProcessInfo.processInfo.systemUptime

        if popover.isShown {
            closePopover()
            return
        }

        // Debounce transient popover auto-dismissal:
        // When clicking the status item while the popover is open, macOS transient dismissal
        // fires right before the button action. If closed within 0.35s, this click was intended
        // to dismiss the popover, so do not immediately reopen it.
        if (now - lastCloseTime) < 0.35 {
            return
        }

        // Activate the application so popover window is interactive immediately
        NSApp.activate(ignoringOtherApps: true)

        let isPinned = PureZipPreferences.shared.pureShelfKeepWindowPinned
        popover.behavior = isPinned ? .applicationDefined : .transient
        syncPopoverAppearance()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        applyPinningState()
        syncPopoverAppearance()
        if let window = popover.contentViewController?.view.window {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func showContextMenu(sender: NSStatusBarButton) {
        let menu = NSMenu(title: "PureZip")
        menu.delegate = self

        let openMainItem = NSMenuItem(title: "打开主窗口", action: #selector(openMainWindowAction), keyEquivalent: "1")
        openMainItem.target = self
        menu.addItem(openMainItem)

        let openBoxItem = NSMenuItem(title: "打开 Pure Shelf", action: #selector(openPureShelfAction), keyEquivalent: "")
        openBoxItem.target = self
        menu.addItem(openBoxItem)

        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !session.shelfItems.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(
                title: "清空 Pure Shelf (\(session.shelfItems.count) 项)",
                action: #selector(clearShelfAction),
                keyEquivalent: ""
            )
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "关于 PureZip", action: #selector(openAboutAction), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 核心要求：右键退出选项 (Quit PureZip)
        let quitItem = NSMenuItem(title: "退出 PureZip", action: #selector(quitAppAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        sender.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        sender.highlight(false)
        sender.isHighlighted = false
        statusItem?.menu = nil
    }

    public func menuDidClose(_ menu: NSMenu) {
        // Reset menu and button highlight so subsequent left clicks trigger statusItemClicked directly
        statusItem?.menu = nil
        statusItem?.button?.isHighlighted = false
        statusItem?.button?.highlight(false)
    }

    // MARK: - Menu Actions

    @objc private func openMainWindowAction() {
        if let popover = popover, popover.isShown {
            closePopover()
        }
        session.openMainWindow()
    }

    @objc private func openPureShelfAction() {
        if let button = statusItem?.button {
            togglePopover(sender: button)
        }
    }

    @objc private func openSettingsAction() {
        session.openSettings(tab: .pureShelf)
    }

    @objc private func clearShelfAction() {
        session.clearShelf()
    }

    @objc private func openAboutAction() {
        session.openSettings(tab: .about)
    }

    @objc private func quitAppAction() {
        NSApp.terminate(nil)
    }
}
