import AppKit
import Foundation
import CoreText
import SwiftUI
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

/// Contextual action kinds supported by Pure Actions.
public enum PureActionKind: String, CaseIterable, Identifiable, Sendable {
    case installApplication = "installApplication"
    case installFont        = "installFont"
    case installPackage     = "installPackage"
    case openNestedArchive  = "openNestedArchive"
    case quickLookPreview   = "quickLookPreview"
    case copyToClipboard    = "copyToClipboard"
    case extractSelection   = "extractSelection"
    case revealInFinder     = "revealInFinder"

    public var id: String { rawValue }
}

public struct PureActionDescriptor: Identifiable, Sendable {
    public let id = UUID()
    public let kind: PureActionKind
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let isPrimary: Bool
    public let badgeText: String?

    public init(
        kind: PureActionKind,
        title: String,
        subtitle: String,
        systemImage: String,
        isPrimary: Bool = false,
        badgeText: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.badgeText = badgeText
    }
}

/// Dynamic contextual action resolver and executor for Pure Actions.
@MainActor
public final class PureActionsRouter {

    public static func isFormatAllowedInPureActions(_ ext: String) -> Bool {
        guard let tag = pureActionsFormatTag(for: ext) else { return true }
        return PureZipPreferences.shared.pureActionsAllowedFormats.contains(tag)
    }

    private static func pureActionsFormatTag(for ext: String) -> String? {
        switch ext.lowercased() {
        case "pdf": return "PDF"
        case "txt", "text", "log": return "纯文本"
        case "md", "markdown": return "Markdown"
        case "rtf": return "RTF"
        case "csv": return "CSV"
        case "doc", "docx": return "Word"
        case "xls", "xlsx": return "Excel"
        case "ppt", "pptx": return "PowerPoint"
        case "epub": return "EPUB"
        case "jpg", "jpeg": return "JPEG"
        case "png": return "PNG"
        case "gif": return "GIF"
        case "webp": return "WebP"
        case "heif", "heic": return "HEIF / HEIC"
        case "tiff", "tif": return "TIFF"
        case "bmp": return "BMP"
        case "svg": return "SVG"
        case "mp3": return "MP3"
        case "m4a", "aac": return "M4A / AAC"
        case "wav": return "WAV"
        case "flac": return "FLAC"
        case "ogg": return "OGG"
        case "mp4", "m4v": return "MP4 / M4V"
        case "mov": return "MOV"
        case "mkv": return "MKV"
        case "webm": return "WebM"
        case "avi": return "AVI"
        case "html", "htm": return "HTML"
        case "xml": return "XML"
        case "json": return "JSON"
        case "yaml", "yml": return "YAML"
        case "plist": return "Plist"
        default: return nil
        }
    }

    /// Inspects the selected entry and infers the optimal contextual Pure Actions.
    public static func resolveActions(for entry: ArchiveEntry) -> [PureActionDescriptor] {
        var actions: [PureActionDescriptor] = []
        let lowerPath = entry.path.lowercased()
        let ext = (entry.name as NSString).pathExtension.lowercased()

        // 1. macOS Application Bundle (.app)
        if lowerPath.contains(".app") || ext == "app" {
            actions.append(PureActionDescriptor(
                kind: .installApplication,
                title: "安装应用",
                subtitle: "直接安装至 /Applications 目录并就绪",
                systemImage: "arrow.down.app.fill",
                isPrimary: true
            ))
        }

        // 2. Font Files (.ttf, .otf, .ttc)
        if ["ttf", "otf", "ttc", "woff", "woff2"].contains(ext) {
            actions.append(PureActionDescriptor(
                kind: .installFont,
                title: "安装字体",
                subtitle: "安装到系统字体库 (~/Library/Fonts) 并即刻激活",
                systemImage: "textformat.size",
                isPrimary: true
            ))
        }

        // 3. System Installer Packages (.pkg, .mpkg)
        if ["pkg", "mpkg"].contains(ext) {
            actions.append(PureActionDescriptor(
                kind: .installPackage,
                title: "运行安装器",
                subtitle: "由系统安装器打开此软件包",
                systemImage: "shippingbox.fill",
                isPrimary: true
            ))
        }

        // 4. Nested Archive Container (.zip, .7z, .tar, .tar.gz, .rar, etc.)
        let dummyURL = URL(fileURLWithPath: "/tmp/\(entry.name)")
        let detected = ArchiveFormatDescriptor.detect(at: dummyURL)
        if detected.format != .unknown && entry.type != .directory {
            actions.append(PureActionDescriptor(
                kind: .openNestedArchive,
                title: "继续深入浏览",
                subtitle: "免解压直接展开嵌套归档",
                systemImage: "arrow.down.right.and.arrow.up.left",
                isPrimary: true
            ))
        }

        // 5. Image & Media Files (.png, .jpg, .svg, .gif, .pdf)
        if ["png", "jpg", "jpeg", "webp", "gif", "heic", "svg", "pdf"].contains(ext) && isFormatAllowedInPureActions(ext) {
            actions.append(PureActionDescriptor(
                kind: .copyToClipboard,
                title: "拷贝图像数据",
                subtitle: "提取并将图片放入剪贴板",
                systemImage: "doc.on.clipboard",
                isPrimary: false
            ))
        }

        // 6. Text / Code / Document files
        if ["txt", "md", "json", "swift", "py", "sh", "yaml", "xml", "html", "c", "cpp"].contains(ext) && isFormatAllowedInPureActions(ext) {
            actions.append(PureActionDescriptor(
                kind: .copyToClipboard,
                title: "拷贝文本内容",
                subtitle: "提取全文并拷贝到剪贴板",
                systemImage: "doc.on.doc",
                isPrimary: false
            ))
        }

        // Default Universal Actions
        actions.append(PureActionDescriptor(
            kind: .extractSelection,
            title: entry.type == .directory ? "解压此文件夹" : "解压选中项",
            subtitle: "输出至归档所在同级目录",
            systemImage: "tray.and.arrow.down",
            isPrimary: actions.isEmpty
        ))

        return actions
    }

    /// Executes the chosen contextual Pure Action.
    public static func execute(
        action: PureActionKind,
        for entry: ArchiveEntry,
        session: ArchiveBrowsingSession
    ) async throws -> String {
        guard let archiveURL = session.currentArchiveURL else {
            throw ArchiveEngineError.io("未打开有效归档")
        }

        switch action {
        case .installApplication:
            // Extract the entire .app bundle to /Applications
            let appRootPath: String
            if let range = entry.path.range(of: ".app") {
                appRootPath = String(entry.path[..<range.upperBound])
            } else {
                appRootPath = entry.path
            }

            let appName = (appRootPath as NSString).lastPathComponent
            let targetURL = URL(fileURLWithPath: "/Applications/\(appName)")

            // Check if already exists in /Applications
            if FileManager.default.fileExists(atPath: targetURL.path) {
                let alert = NSAlert()
                alert.messageText = "应用程序已存在"
                alert.informativeText = "/Applications 目录下已存在同名程序 \"\(appName)\"，是否替换？"
                alert.addButton(withTitle: "替换并安装")
                alert.addButton(withTitle: "取消")
                if alert.runModal() != .alertFirstButtonReturn {
                    return "已取消应用安装"
                }
                try? FileManager.default.removeItem(at: targetURL)
            }

            let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "pureaction_app")
            defer { stageLease.release() }

            // Extract entries belonging to the .app bundle
            let index = session.entryIndex
            let appEntries = (try? index?.descendants(of: appRootPath)) ?? [entry]
            try await session.broker.extract(archiveURL, entries: appEntries, to: stageLease.url)

            let extractedAppURL = stageLease.url.appendingPathComponent(appRootPath)
            guard FileManager.default.fileExists(atPath: extractedAppURL.path) else {
                throw ArchiveEngineError.io("未能提取完整的应用程序包: \(appRootPath)")
            }

            try FileManager.default.moveItem(at: extractedAppURL, to: targetURL)

            // Pure Actions Quick Install: remove quarantine tag if enabled
            if PureZipPreferences.shared.pureActionsQuickInstall {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                p.arguments = ["-dr", "com.apple.quarantine", targetURL.path]
                try? p.run()
                p.waitUntilExit()
            }

            // 1. DMG Post-Install Special Action: Auto eject DMG & confirm delete
            let isDMG = archiveURL.pathExtension.lowercased() == "dmg" || archiveURL.path.hasPrefix("/Volumes/")
            if isDMG {
                DiskImageEngine.detach(diskImageURL: archiveURL)

                let alert = NSAlert()
                alert.messageText = "安装完成"
                alert.informativeText = "“\(appName)”已成功安装到“应用程序”文件夹。已自动推出磁盘映像。是否将原 DMG 文件移入废纸篓？"
                alert.addButton(withTitle: "移入废纸篓")
                alert.addButton(withTitle: "保留 DMG")
                alert.alertStyle = .informational

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.recycle([archiveURL]) { _, _ in }
                    session.closeArchive()
                    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                    return "已将 “\(appName)” 安装至 /Applications，并已推出且移除 DMG 映像"
                } else {
                    session.closeArchive()
                    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                    return "已将 “\(appName)” 安装至 /Applications，并已自动推出 DMG 映像"
                }
            }

            // 2. Standard Archive Post-Install Action
            switch PureZipPreferences.shared.pureActionsPostAction {
            case "移入废纸篓":
                NSWorkspace.shared.recycle([archiveURL]) { _, _ in }
            case "每次均询问":
                let alert = NSAlert()
                alert.messageText = "应用安装完成"
                alert.informativeText = "应用 \"\(appName)\" 已成功安装至 /Applications。是否将原压缩包移入废纸篓？"
                alert.addButton(withTitle: "保留压缩包")
                alert.addButton(withTitle: "移入废纸篓")
                if alert.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.recycle([archiveURL]) { _, _ in }
                }
            default:
                break
            }

            // Pure Actions Auto Close: Dismiss window if enabled
            if PureZipPreferences.shared.pureActionsAutoClose {
                session.currentArchiveURL = nil
            }

            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            return "成功将 \"\(appName)\" 安装至 /Applications！"

        case .installFont:
            let fontsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Fonts")
            try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)

            let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "pureaction_font")
            defer { stageLease.release() }

            try await session.broker.extract(archiveURL, entries: [entry], to: stageLease.url)
            let extractedFontURL = stageLease.url.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: extractedFontURL.path) else {
                throw ArchiveEngineError.io("未能提取字体文件: \(entry.name)")
            }

            let destinationURL = fontsDir.appendingPathComponent(entry.name)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: extractedFontURL, to: destinationURL)

            // Register dynamically via CoreText
            var errorRef: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(destinationURL as CFURL, .process, &errorRef)
            if success {
                return "已成功安装并即时激活字体 \"\(entry.name)\"！"
            } else {
                let errDesc = errorRef?.takeRetainedValue().localizedDescription ?? "未知错误"
                return "字体已复制至 ~/Library/Fonts，激活提示: \(errDesc)"
            }

        case .installPackage:
            let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "pureaction_pkg")
            try await session.broker.extract(archiveURL, entries: [entry], to: stageLease.url)
            let pkgURL = stageLease.url.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: pkgURL.path) else {
                throw ArchiveEngineError.io("未能提取安装包: \(entry.name)")
            }
            NSWorkspace.shared.open(pkgURL)
            return "已启动系统安装器处理 \"\(entry.name)\""

        case .openNestedArchive:
            await session.openNestedArchive(entry: entry)
            return "已展开嵌套归档 \"\(entry.name)\""

        case .copyToClipboard:
            let stageLease = try ManagedWorkFileStore.shared.makeStagingLease(prefix: "pureaction_copy")
            defer { stageLease.release() }
            try await session.broker.extract(archiveURL, entries: [entry], to: stageLease.url)
            let fileURL = stageLease.url.appendingPathComponent(entry.path)
            guard let data = try? Data(contentsOf: fileURL) else {
                throw ArchiveEngineError.io("未能读取条目内容")
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            if let image = NSImage(data: data) {
                pb.writeObjects([image])
                return "已将图像 \"\(entry.name)\" 拷贝至剪贴板"
            } else if let text = String(data: data, encoding: .utf8) {
                pb.setString(text, forType: .string)
                return "已将文本内容拷贝至剪贴板 (\(text.count) 字)"
            } else {
                pb.setData(data, forType: .fileURL)
                return "已将文件数据写入剪贴板"
            }

        case .extractSelection:
            let destination = archiveURL.deletingLastPathComponent()
            await session.extractArchive(entries: [entry], to: destination)
            return "已将 \"\(entry.name)\" 解压至 \(destination.lastPathComponent)"

        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
            return "已在访达中定位归档文件"

        case .quickLookPreview:
            await session.loadEntryPreview(for: entry)
            return "已加载预览"
        }
    }
}
