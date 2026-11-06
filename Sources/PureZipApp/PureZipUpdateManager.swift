//
//  PureZipUpdateManager.swift
//  PureZip
//
//  GitHub Releases update checker for Minato-chen/PureZip.
//

import Foundation
import AppKit
import Combine

public struct GitHubReleaseInfo: Sendable {
    public let tagName: String
    public let name: String
    public let body: String
    public let htmlURL: URL
    public let downloadURL: URL?
    public let publishedAt: String
}

@MainActor
public final class PureZipUpdateManager: ObservableObject {
    public static let shared = PureZipUpdateManager()

    public static let repoOwner = "Minato-chen"
    public static let repoName = "PureZip"
    public static let releasesAPI = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    public static let releasesWebURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    public static let repoWebURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)")!
    public static let issuesWebURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/issues")!

    @Published public var isChecking: Bool = false
    @Published public var latestRelease: GitHubReleaseInfo? = nil
    @Published public var hasNewVersion: Bool = false
    @Published public var statusMessage: String = "尚未检查更新"
    @Published public var lastCheckedDate: Date? = nil
    @Published public var checkError: String? = nil

    // In-app update state
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadSpeedMBs: Double = 0.0
    @Published public var updatePhaseText: String = ""
    @Published public var updateErrorMessage: String? = nil

    private var currentDownloadSession: URLSession?
    private var currentDownloadTask: URLSessionDownloadTask?

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "255"
    }

    public var versionDisplayString: String {
        "\(currentVersion) (\(currentBuild))"
    }

    public var systemArchString: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Universal"
        #endif
    }

    public init() {}

    public func checkForUpdates(userInitiated: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
        checkError = nil
        if userInitiated {
            statusMessage = "正在连接 GitHub 检查更新..."
        }

        let currentVer = self.currentVersion
        let apiURL = Self.releasesAPI

        Task {
            do {
                var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12.0)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                request.setValue("PureZip-UpdateChecker/\(currentVer)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if httpResponse.statusCode == 404 {
                    // No releases published yet on GitHub repo
                    self.isChecking = false
                    self.lastCheckedDate = Date()
                    self.hasNewVersion = false
                    self.statusMessage = "已是最新版本 (\(currentVer))"
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "GitHub 返回状态码 \(httpResponse.statusCode)"
                    ])
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rawTag = json["tag_name"] as? String else {
                    throw NSError(domain: "GitHubAPI", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "无法解析 GitHub 发行版本数据"
                    ])
                }

                let releaseName = json["name"] as? String ?? rawTag
                let body = json["body"] as? String ?? ""
                let htmlURLStr = json["html_url"] as? String ?? Self.releasesWebURL.absoluteString
                let htmlURL = URL(string: htmlURLStr) ?? Self.releasesWebURL
                let publishedAt = json["published_at"] as? String ?? ""

                // Find download URL in assets (.dmg or .zip)
                var downloadURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    #if arch(arm64)
                    let preferredArch = "arm64"
                    #elseif arch(x86_64)
                    let preferredArch = "x86_64"
                    #else
                    let preferredArch = ""
                    #endif

                    // 1. Try to find DMG matching current architecture
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".dmg"),
                           !preferredArch.isEmpty,
                           name.localizedCaseInsensitiveContains(preferredArch),
                           let browserURLStr = asset["browser_download_url"] as? String,
                           let u = URL(string: browserURLStr) {
                            downloadURL = u
                            break
                        }
                    }

                    // 2. Fall back to any .dmg
                    if downloadURL == nil {
                        for asset in assets {
                            if let name = asset["name"] as? String,
                               name.hasSuffix(".dmg"),
                               let browserURLStr = asset["browser_download_url"] as? String,
                               let u = URL(string: browserURLStr) {
                                downloadURL = u
                                break
                            }
                        }
                    }

                    // 3. Fall back to .zip
                    if downloadURL == nil {
                        for asset in assets {
                            if let name = asset["name"] as? String,
                               name.hasSuffix(".zip"),
                               let browserURLStr = asset["browser_download_url"] as? String,
                               let u = URL(string: browserURLStr) {
                                downloadURL = u
                                break
                            }
                        }
                    }
                }

                let info = GitHubReleaseInfo(
                    tagName: rawTag,
                    name: releaseName,
                    body: body,
                    htmlURL: htmlURL,
                    downloadURL: downloadURL ?? htmlURL,
                    publishedAt: publishedAt
                )

                let isNewer = Self.compareVersion(rawTag, greaterThan: currentVer)

                self.isChecking = false
                self.lastCheckedDate = Date()
                self.latestRelease = info
                self.hasNewVersion = isNewer

                if isNewer {
                    self.statusMessage = "发现新版本: \(rawTag)"
                } else {
                    self.statusMessage = "已是最新版本 (\(currentVer))"
                }

            } catch {
                self.isChecking = false
                self.checkError = error.localizedDescription
                self.statusMessage = "检查更新失败: \(error.localizedDescription)"
            }
        }
    }

    public static func compareVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return clean1.compare(clean2, options: .numeric) == .orderedDescending
    }

    // MARK: - In-App Self Update

    public func cancelDownload() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        currentDownloadSession?.invalidateAndCancel()
        currentDownloadSession = nil
        isDownloading = false
        downloadProgress = 0.0
        downloadSpeedMBs = 0.0
        updatePhaseText = ""
    }

    public func startInAppUpdate(release: GitHubReleaseInfo) {
        guard !isDownloading else { return }
        guard let url = release.downloadURL,
              (url.pathExtension.lowercased() == "dmg" || url.pathExtension.lowercased() == "zip") else {
            self.updateErrorMessage = "未找到可直接安装的更新包（.dmg/.zip），请前往网页下载。"
            return
        }

        // Determine destination target application path
        let currentAppURL = Bundle.main.bundleURL
        let targetAppPath: String
        if currentAppURL.path.hasPrefix("/Applications/") {
            targetAppPath = currentAppURL.path
        } else if FileManager.default.fileExists(atPath: "/Applications/PureZip.app") {
            targetAppPath = "/Applications/PureZip.app"
        } else {
            targetAppPath = currentAppURL.path
        }

        let targetParentDir = (targetAppPath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: targetParentDir) else {
            self.updateErrorMessage = "安装目录无写入权限（\(targetParentDir)），请前往网页下载。"
            return
        }

        isDownloading = true
        downloadProgress = 0.0
        downloadSpeedMBs = 0.0
        updateErrorMessage = nil
        updatePhaseText = "正在连接下载更新包..."

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 600.0

        let delegate = UpdateDownloadDelegate(
            onProgress: { [weak self] progress, speedMBs in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isDownloading else { return }
                    self.downloadProgress = progress
                    if speedMBs >= 0 {
                        self.downloadSpeedMBs = speedMBs
                    }
                    self.updatePhaseText = "正在下载更新包 (\(Int(progress * 100))%)"
                }
            },
            onCompletion: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentDownloadTask = nil
                    self.currentDownloadSession?.finishTasksAndInvalidate()
                    self.currentDownloadSession = nil

                    switch result {
                    case .success(let payloadURL):
                        self.updatePhaseText = "下载完成，正在准备安装..."
                        self.installUpdate(payloadURL: payloadURL, targetAppPath: targetAppPath)
                    case .failure(let error):
                        self.isDownloading = false
                        self.updateErrorMessage = "下载失败: \(error.localizedDescription)"
                        self.updatePhaseText = ""
                    }
                }
            }
        )

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.currentDownloadSession = session

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        request.setValue("PureZip-Updater/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request)
        self.currentDownloadTask = task
        task.resume()
    }

    private func installUpdate(payloadURL: URL, targetAppPath: String) {
        Task.detached(priority: .userInitiated) {
            do {
                let fileManager = FileManager.default
                let payloadDir = payloadURL.deletingLastPathComponent()
                let ext = payloadURL.pathExtension.lowercased()

                let sourceAppPath: String
                let mountDir: URL?

                if ext == "dmg" {
                    let mountURL = payloadDir.appendingPathComponent("mount")
                    try? fileManager.removeItem(at: mountURL)
                    try fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)

                    let attachProcess = Process()
                    attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    attachProcess.arguments = [
                        "attach", payloadURL.path,
                        "-readonly", "-nobrowse", "-noautoopen",
                        "-mountpoint", mountURL.path
                    ]
                    try attachProcess.run()
                    attachProcess.waitUntilExit()

                    guard attachProcess.terminationStatus == 0 else {
                        throw NSError(domain: "PureZipUpdater", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "挂载更新磁盘镜像失败 (code: \(attachProcess.terminationStatus))"
                        ])
                    }
                    mountDir = mountURL

                    let candidate = mountURL.appendingPathComponent("PureZip.app")
                    guard fileManager.fileExists(atPath: candidate.path) else {
                        let detach = Process()
                        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                        detach.arguments = ["detach", mountURL.path, "-force"]
                        try? detach.run()
                        detach.waitUntilExit()
                        throw NSError(domain: "PureZipUpdater", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "更新镜像中未包含 PureZip.app"
                        ])
                    }
                    sourceAppPath = candidate.path
                } else if ext == "zip" {
                    mountDir = nil
                    let extractDir = payloadDir.appendingPathComponent("extracted")
                    try? fileManager.removeItem(at: extractDir)
                    try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

                    let dittoProcess = Process()
                    dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    dittoProcess.arguments = ["-xk", payloadURL.path, extractDir.path]
                    try dittoProcess.run()
                    dittoProcess.waitUntilExit()

                    let candidate = extractDir.appendingPathComponent("PureZip.app")
                    guard fileManager.fileExists(atPath: candidate.path) else {
                        throw NSError(domain: "PureZipUpdater", code: 3, userInfo: [
                            NSLocalizedDescriptionKey: "更新压缩包中未包含 PureZip.app"
                        ])
                    }
                    sourceAppPath = candidate.path
                } else {
                    throw NSError(domain: "PureZipUpdater", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: "不受支持的安装包格式: .\(ext)"
                    ])
                }

                // Create detached updater script
                let scriptURL = payloadDir.appendingPathComponent("replace_and_relaunch.sh")
                let scriptContent = """
                #!/bin/bash
                trap '' HUP INT TERM

                TARGET_PID="$1"
                MOUNT_DIR="$2"
                SOURCE_APP="$3"
                TARGET_APP="$4"
                PAYLOAD_DIR="$5"

                COUNT=0
                while kill -0 "$TARGET_PID" 2>/dev/null; do
                    sleep 0.2
                    COUNT=$((COUNT+1))
                    if [ $COUNT -ge 75 ]; then
                        kill -9 "$TARGET_PID" 2>/dev/null || true
                        break
                    fi
                done

                # Atomic replacement
                rm -rf "$TARGET_APP"
                cp -R "$SOURCE_APP" "$TARGET_APP"

                # Strip quarantine flag
                xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

                # Detach DMG if mounted
                if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
                    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
                fi

                # Cleanup temporary payload
                rm -rf "$PAYLOAD_DIR"

                # Relaunch
                open "$TARGET_APP"
                """

                try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

                let currentPID = String(ProcessInfo.processInfo.processIdentifier)
                let runner = Process()
                runner.executableURL = URL(fileURLWithPath: "/bin/bash")
                runner.arguments = [
                    scriptURL.path,
                    currentPID,
                    mountDir?.path ?? "",
                    sourceAppPath,
                    targetAppPath,
                    payloadDir.path
                ]
                try runner.run()

                await MainActor.run {
                    self.updatePhaseText = "正在重启完成更新..."
                }

                // Short sleep before terminate to ensure process started
                try? await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    NSApp.terminate(nil)
                }

            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.updateErrorMessage = "安装准备失败: \(error.localizedDescription)"
                    self.updatePhaseText = ""
                }
            }
        }
    }
}

// MARK: - Update Download Delegate

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double, Double) -> Void
    private let onCompletion: @Sendable (Result<URL, Error>) -> Void
    private var lastBytes: Int64 = 0
    private var lastTime: Date = Date()

    init(
        onProgress: @escaping @Sendable (Double, Double) -> Void,
        onCompletion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress: Double = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        if elapsed >= 0.4 {
            let bytesDelta = totalBytesWritten - lastBytes
            let speedMBs = (Double(bytesDelta) / (1024.0 * 1024.0)) / elapsed
            lastBytes = totalBytesWritten
            lastTime = now
            onProgress(progress, speedMBs)
        } else {
            onProgress(progress, -1)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PureZipUpdatePayload-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let ext = downloadTask.originalRequest?.url?.pathExtension.isEmpty == false ? (downloadTask.originalRequest?.url?.pathExtension ?? "dmg") : "dmg"
            let targetURL = tempDir.appendingPathComponent("payload.\(ext)")
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: location, to: targetURL)
            onCompletion(.success(targetURL))
        } catch {
            onCompletion(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                return
            }
            onCompletion(.failure(error))
        }
    }
}
