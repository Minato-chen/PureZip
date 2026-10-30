import AppKit
import SwiftUI
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

/// Application delegate managing menu bar integration, keyboard shortcuts, and macOS Services (`performPureZipService:userData:error:`).
@MainActor
public final class PureZipApplicationDelegate: NSObject, NSApplicationDelegate {
    public let session = ArchiveBrowsingSession()
    private var statusItemController: PureZipStatusItemController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("PureZip resident menu bar and background integration")
        NSApp.servicesProvider = self
        NSApp.setActivationPolicy(.regular)
        applyApplicationIconIfAvailable()
        NSApp.activate(ignoringOtherApps: true)
        PureZipPreferences.shared.syncAppearance()

        // Initialize status item with left-click PureShelf popover & right-click context menu (Quit)
        statusItemController = PureZipStatusItemController(session: session)

        // Install local monitor for Spacebar (keyCode 49) to toggle native macOS QuickLook
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 49 { // Spacebar
                if let window = NSApp.keyWindow,
                   let responder = window.firstResponder,
                   responder.isKind(of: NSTextView.self) || responder.isKind(of: NSTextField.self) {
                    return event
                }
                self?.session.toggleQuickLookForSelected()
                return nil
            }
            return event
        }

        // Check command line file path argument if provided
        let args = Array(CommandLine.arguments.dropFirst())
        if let firstPath = args.first(where: { !$0.hasPrefix("-") }) {
            let url = URL(fileURLWithPath: firstPath)
            if FileManager.default.fileExists(atPath: url.path) {
                Task {
                    if PureZipPreferences.shared.quickExtractOnDoubleClick {
                        await session.openArchive(at: url)
                        await session.extractArchive(entries: [], to: url.deletingLastPathComponent())
                    } else {
                        await session.openArchive(at: url)
                    }
                }
            }
        }

        // Auto-register Finder extension and LaunchServices in background for dev/local testing
        registerSystemIntegrationIfNeeded()
    }

    /// Explicitly binds `NSApp.applicationIconImage` from `AppIcon.icns` so Dock/Switcher icons are guaranteed even in debug/CLI launches
    private func applyApplicationIconIfAvailable() {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns"),
            URL(fileURLWithPath: "/Applications/PureZip.app/Contents/Resources/AppIcon.icns")
        ]
        for url in candidateURLs.compactMap({ $0 }) {
            if let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
                return
            }
        }
    }

    /// Automatically ensure LaunchServices and FinderSync are registered so Cmd+R or local launch immediately works
    private func registerSystemIntegrationIfNeeded() {
        Task.detached(priority: .background) {
            let bundleURL = Bundle.main.bundleURL
            // If running inside dist/ or DerivedData or /Applications, register to LaunchServices & pluginkit
            let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            if FileManager.default.fileExists(atPath: lsregisterPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: lsregisterPath)
                process.arguments = ["-f", bundleURL.path]
                try? process.run()
            }

            let finderSyncPath = bundleURL.appendingPathComponent("Contents/PlugIns/PureZipFinderSync.appex").path
            if FileManager.default.fileExists(atPath: finderSyncPath) {
                let addProc = Process()
                addProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
                addProc.arguments = ["-a", finderSyncPath]
                try? addProc.run()
                addProc.waitUntilExit()

                let useProc = Process()
                useProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
                useProc.arguments = ["-e", "use", "-i", "com.minato.purezip.FinderSync"]
                try? useProc.run()
            }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            session.openMainWindow()
        }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if session.hasUnsavedChanges && !session.isCapsuleMode {
            switch PureZipPreferences.shared.deskUnsavedChangesAction {
            case "autoSave":
                Task {
                    await session.savePendingChanges()
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
                return .terminateLater
            case "discard":
                return .terminateNow
            default: // "ask"
                let alert = NSAlert()
                alert.messageText = "存在未保存的修改"
                alert.informativeText = "退出应用前，是否保存当前归档中的修改？"
                alert.addButton(withTitle: "保存并退出")
                alert.addButton(withTitle: "放弃修改并退出")
                alert.addButton(withTitle: "取消")
                let resp = alert.runModal()
                if resp == .alertFirstButtonReturn {
                    Task {
                        await session.savePendingChanges()
                        NSApp.reply(toApplicationShouldTerminate: true)
                    }
                    return .terminateLater
                } else if resp == .alertSecondButtonReturn {
                    return .terminateNow
                } else {
                    return .terminateCancel
                }
            }
        }
        return .terminateNow
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        if urls.count > 1 {
            BatchExtractionManager.shared.startBatch(urls: urls)
        } else if let url = urls.first {
            Task {
                if PureZipPreferences.shared.quickExtractOnDoubleClick {
                    await session.openArchive(at: url)
                    await session.extractArchive(entries: [], to: url.deletingLastPathComponent())
                } else {
                    await session.handleIncomingURL(url)
                }
            }
        }
    }

    @objc public func performPureZipService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let items = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !items.isEmpty else {
            return
        }
        let actionName = userData ?? "browseArchive"
        Task { @MainActor in
            switch actionName {
            case "extractHere":
                if items.count > 1 {
                    BatchExtractionManager.shared.startBatch(urls: items)
                } else if let single = items.first {
                    await session.openArchive(at: single)
                    await session.extractArchive(entries: [], to: single.deletingLastPathComponent())
                }
            case "compressDefault", "compressConfigured":
                if let dest = try? FinderArchiveNaming.availableZIPDestination(for: items) {
                    await session.createArchive(sources: items, destinationURL: dest, format: .zip)
                }
            case "sendToPureZip":
                session.addToShelf(items)
            default:
                if let first = items.first {
                    await session.openArchive(at: first)
                }
            }
        }
    }
}

struct PureZipAppScene: App {
    @NSApplicationDelegateAdaptor(PureZipApplicationDelegate.self) var appDelegate

    var body: some Scene {
        Window("PureZip", id: "main") {
            RootApplicationView(session: appDelegate.session)
                .frame(minWidth: 360, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
                .onOpenURL { url in
                    Task { await appDelegate.session.handleIncomingURL(url) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("文件") {
                Button("打开主窗口") {
                    appDelegate.session.openMainWindow()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Divider()

                Button("新建归档...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = true
                    panel.prompt = "选择要压缩的文件"
                    if panel.runModal() == .OK, !panel.urls.isEmpty {
                        appDelegate.session.creationSources = panel.urls
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("打开归档...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.prompt = "打开"
                    if panel.runModal() == .OK, let url = panel.url {
                        Task { await appDelegate.session.openArchive(at: url) }
                    }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Divider()

                Button("关闭归档") {
                    appDelegate.session.closeArchive()
                }
                .keyboardShortcut("w", modifiers: [.command])

                Button("偏好设置...") {
                    appDelegate.session.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("归档操作") {
                Button("刷新当前归档") {
                    Task { await appDelegate.session.reloadArchiveInPlace() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("快速预览 (QuickLook)") {
                    appDelegate.session.toggleQuickLookForSelected()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("向归档添加文件...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    panel.prompt = "添加至归档"
                    if panel.runModal() == .OK, !panel.urls.isEmpty {
                        Task { await appDelegate.session.addFilesToCurrentArchive(panel.urls) }
                    }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("生成并打开示例归档") {
                    Task { await appDelegate.session.generateAndOpenDemoArchive() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("切换 Pure Desk / Pure Capsule") {
                    appDelegate.session.toggleWindowMode()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("校验当前归档 CRC32") {
                    Task { await appDelegate.session.testCurrentArchiveIntegrity() }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}

@main
struct PureZipAppMain {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            print("PureZipApp GUI binary ready (CompleteDesk + CapsuleFloating + MenuBarExtra)")
            return
        }
        PureZipAppScene.main()
    }
}
