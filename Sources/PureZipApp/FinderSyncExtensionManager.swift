import AppKit
import Foundation

/// Manages registration, health check, and system repair for the PureZip FinderSync extension.
@MainActor
public final class FinderSyncExtensionManager: ObservableObject {
    public static let shared = FinderSyncExtensionManager()

    @Published public var isRegistered: Bool = false
    @Published public var isChecking: Bool = false
    @Published public var statusMessage: String = ""

    public init() {
        checkStatus()
    }

    /// Checks pluginkit status for com.minato.purezip.FinderSync
    public func checkStatus() {
        isChecking = true
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            process.arguments = ["-m", "-v", "-i", "com.minato.purezip.FinderSync"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let active = output.contains("+") && output.contains("com.minato.purezip.FinderSync")

            Task { @MainActor in
                FinderSyncExtensionManager.shared.isRegistered = active
                FinderSyncExtensionManager.shared.statusMessage = active ? "已就绪并在访达中启用" : "未在系统扩展中启用或待重新注册"
                FinderSyncExtensionManager.shared.isChecking = false
            }
        }
    }

    /// Re-registers FinderSync extension with macOS LaunchServices and restarts Finder
    public func repairAndRegister(bundleURL: URL? = nil) async {
        isChecking = true
        statusMessage = "正在重新注册扩展并刷新访达..."

        let candidatePaths = [
            bundleURL?.appendingPathComponent("Contents/PlugIns/PureZipFinderSync.appex").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/PureZipFinderSync.appex").path,
            "/Applications/PureZip.app/Contents/PlugIns/PureZipFinderSync.appex"
        ].compactMap { $0 }

        let foundAppex = candidatePaths.first { FileManager.default.fileExists(atPath: $0) }
        guard let appexPath = foundAppex else {
            statusMessage = "未找到 PureZipFinderSync.appex，请确保应用已安装至 /Applications"
            isChecking = false
            return
        }

        // 1. Tell LaunchServices to register the parent .app bundle
        let parentAppPath = URL(fileURLWithPath: appexPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.fileExists(atPath: lsregister) {
            let lsProc = Process()
            lsProc.executableURL = URL(fileURLWithPath: lsregister)
            lsProc.arguments = ["-f", "-R", "-trusted", parentAppPath]
            try? lsProc.run()
            lsProc.waitUntilExit()
        }

        // 2. Add with pluginkit
        let addProc = Process()
        addProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        addProc.arguments = ["-a", appexPath]
        try? addProc.run()
        addProc.waitUntilExit()

        // 3. Enable with pluginkit
        let useProc = Process()
        useProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        useProc.arguments = ["-e", "use", "-i", "com.minato.purezip.FinderSync"]
        try? useProc.run()
        useProc.waitUntilExit()

        // 4. Restart Finder so it hooks up immediately
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProc.arguments = ["Finder"]
        try? killProc.run()
        killProc.waitUntilExit()

        // Wait brief moment and recheck
        try? await Task.sleep(nanoseconds: 600_000_000)
        checkStatus()
    }

    /// Opens macOS System Settings directly to Extensions pane
    public func openSystemSettingsExtensions() {
        let urls = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ]
        for urlStr in urls {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
