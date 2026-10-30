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
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           (name.hasSuffix(".dmg") || name.hasSuffix(".zip")),
                           let browserURLStr = asset["browser_download_url"] as? String,
                           let u = URL(string: browserURLStr) {
                            downloadURL = u
                            break
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
}
