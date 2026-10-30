//
//  ArchiveAssociationStore.swift
//  PureZip
//
//  Fine-grained, categorized file association store & manager.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import CoreServices
import Combine

public enum ArchiveAssociationSection: String, CaseIterable, Identifiable, Sendable {
    case common      = "常用归档格式"
    case streams     = "压缩数据流"
    case volumes     = "分卷与专用包"
    case containers  = "磁盘与容器镜像"

    public var id: String { rawValue }

    public var title: String { rawValue }

    public var subtitle: String {
        switch self {
        case .common: return "日常最常用的压缩与归档文件"
        case .streams: return "通常用于下载和传输的压缩数据流"
        case .volumes: return "大文件分割切片与专用软件包"
        case .containers: return "磁盘映像与光盘容器文件"
        }
    }

    public var icon: String {
        switch self {
        case .common: return "archivebox.fill"
        case .streams: return "waveform.path"
        case .volumes: return "square.split.2x2"
        case .containers: return "opticaldisc.fill"
        }
    }
}

public struct ArchiveExtensionItem: Identifiable, Sendable {
    public let id: String
    public let ext: String
    public let displayExt: String
    public let title: String
    public let desc: String
    public let section: ArchiveAssociationSection
    public let utiIdentifiers: [String]
    public let isRecommended: Bool

    public init(
        id: String,
        ext: String,
        displayExt: String,
        title: String,
        desc: String,
        section: ArchiveAssociationSection,
        utiIdentifiers: [String],
        isRecommended: Bool = false
    ) {
        self.id = id
        self.ext = ext
        self.displayExt = displayExt
        self.title = title
        self.desc = desc
        self.section = section
        self.utiIdentifiers = utiIdentifiers
        self.isRecommended = isRecommended
    }
}

public enum AssociationCoverage: Equatable, Sendable {
    case associated
    case partial
    case unassociated

    public var title: String {
        switch self {
        case .associated: return "已关联"
        case .partial: return "部分关联"
        case .unassociated: return "未关联"
        }
    }
}

public struct ArchiveFileAssociationDescriptor: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let extDisplay: String
    public let desc: String
    public let section: ArchiveAssociationSection
    public let extensions: [String]
    public let isRisk: Bool
    public let utiIdentifiers: [String]

    public var extensionCount: Int { extensions.count }
}

@MainActor
public final class ArchiveAssociationStore: ObservableObject {
    public static let shared = ArchiveAssociationStore()

    @Published public var items: [ArchiveExtensionItem] = []
    @Published public var defaultAppNameByID: [String: String] = [:]
    @Published public var isPureZipByID: [String: Bool] = [:]
    @Published public var updatingIDs: Set<String> = []
    @Published public var isRefreshing: Bool = false
    @Published public var expandedSections: Set<String> = [ArchiveAssociationSection.common.rawValue]

    // Compatibility properties
    @Published public var descriptors: [ArchiveFileAssociationDescriptor] = []
    @Published public var coverageByID: [String: AssociationCoverage] = [:]
    @Published public var associatedExtensionCount: Int = 0
    @Published public var totalExtensionCount: Int = 0
    @Published public var statusMessage: String? = nil

    private let bundleIdentifier: String

    public init() {
        self.bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.minato.purezip"
        self.items = Self.buildCatalog()
        self.descriptors = self.items.map { item in
            ArchiveFileAssociationDescriptor(
                id: item.id,
                title: item.title,
                extDisplay: item.displayExt,
                desc: item.desc,
                section: item.section,
                extensions: [item.ext],
                isRisk: false,
                utiIdentifiers: item.utiIdentifiers
            )
        }
        self.totalExtensionCount = self.items.count

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        refresh()
    }

    public static func buildCatalog() -> [ArchiveExtensionItem] {
        var list: [ArchiveExtensionItem] = []

        // 1. 常用归档格式 (Common)
        list.append(ArchiveExtensionItem(
            id: "zip",
            ext: "zip",
            displayExt: ".zip",
            title: "ZIP 压缩包",
            desc: "跨平台标准归档格式",
            section: .common,
            utiIdentifiers: ["public.zip-archive", "com.pkware.zip-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "7z",
            ext: "7z",
            displayExt: ".7z",
            title: "7-Zip 压缩包",
            desc: "高压缩比 LZMA2 归档",
            section: .common,
            utiIdentifiers: ["org.7-zip.7-zip-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "rar",
            ext: "rar",
            displayExt: ".rar",
            title: "RAR 压缩包",
            desc: "常见互联网分发格式",
            section: .common,
            utiIdentifiers: ["com.rarlab.rar-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "tar",
            ext: "tar",
            displayExt: ".tar",
            title: "TAR 归档",
            desc: "POSIX 标准无压缩归档",
            section: .common,
            utiIdentifiers: ["public.tar-archive", "org.gnu.gnu-tar-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "tgz",
            ext: "tgz",
            displayExt: ".tgz .tar.gz",
            title: "TAR.GZ / TGZ 归档",
            desc: "Gzip 压缩的 Unix 归档",
            section: .common,
            utiIdentifiers: ["org.gnu.gnu-zip-tar-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "tbz",
            ext: "tbz",
            displayExt: ".tbz .tbz2 .tar.bz2",
            title: "TAR.BZ2 归档",
            desc: "Bzip2 压缩的 TAR 归档",
            section: .common,
            utiIdentifiers: ["public.tar-bzip2-archive"]
        ))

        list.append(ArchiveExtensionItem(
            id: "txz",
            ext: "txz",
            displayExt: ".txz .tar.xz",
            title: "TAR.XZ 归档",
            desc: "XZ 压缩的高压缩比 TAR 包",
            section: .common,
            utiIdentifiers: ["org.tukaani.tar-xz-archive"]
        ))

        list.append(ArchiveExtensionItem(
            id: "cbr",
            ext: "cbr",
            displayExt: ".cbr",
            title: "Comic RAR 漫画包",
            desc: "以 RAR 封装的连环漫画归档",
            section: .common,
            utiIdentifiers: ["cx.c3.cbr-archive", "com.minato.purezip.cbr"]
        ))

        list.append(ArchiveExtensionItem(
            id: "cbz",
            ext: "cbz",
            displayExt: ".cbz",
            title: "Comic ZIP 漫画包",
            desc: "以 ZIP 封装的连环漫画归档",
            section: .common,
            utiIdentifiers: ["cx.c3.cbz-archive", "com.minato.purezip.cbz"]
        ))

        // 2. 压缩数据流 (Streams)
        list.append(ArchiveExtensionItem(
            id: "gz",
            ext: "gz",
            displayExt: ".gz",
            title: "Gzip 压缩流",
            desc: "单文件 Gzip 压缩流",
            section: .streams,
            utiIdentifiers: ["org.gnu.gnu-zip-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "bz2",
            ext: "bz2",
            displayExt: ".bz2",
            title: "Bzip2 压缩流",
            desc: "高压缩率的单文件数据流",
            section: .streams,
            utiIdentifiers: ["public.bzip2-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "xz",
            ext: "xz",
            displayExt: ".xz",
            title: "XZ 压缩流",
            desc: "LZMA2 算法高压缩率单文件流",
            section: .streams,
            utiIdentifiers: ["org.tukaani.xz-archive"],
            isRecommended: true
        ))

        list.append(ArchiveExtensionItem(
            id: "lzma",
            ext: "lzma",
            displayExt: ".lzma",
            title: "LZMA 压缩流",
            desc: "经典 LZMA 算法数据流",
            section: .streams,
            utiIdentifiers: ["org.7-zip.lzma-archive"]
        ))

        list.append(ArchiveExtensionItem(
            id: "lz",
            ext: "lz",
            displayExt: ".lz",
            title: "Lzip 压缩流",
            desc: "Lzip 数据归档流",
            section: .streams,
            utiIdentifiers: ["org.nongnu.lzip-archive"]
        ))

        list.append(ArchiveExtensionItem(
            id: "zst",
            ext: "zst",
            displayExt: ".zst",
            title: "Zstandard 压缩流",
            desc: "极速解压的现代数据流",
            section: .streams,
            utiIdentifiers: ["org.facebook.zstandard-archive"]
        ))

        // 3. 分卷与专用包 (Volumes)
        list.append(ArchiveExtensionItem(
            id: "split_num",
            ext: "001",
            displayExt: ".001 - .999",
            title: "数字分卷切片",
            desc: "7-Zip / 通用工具生成的连续分卷包",
            section: .volumes,
            utiIdentifiers: ["com.minato.purezip.numeric-split-volume", "com.minato.purezip.numeric-split-volume"]
        ))

        list.append(ArchiveExtensionItem(
            id: "split_zip",
            ext: "z01",
            displayExt: ".z01 - .z99",
            title: "ZIP 分卷切片",
            desc: "ZIP 格式的多卷压缩切片",
            section: .volumes,
            utiIdentifiers: ["com.minato.purezip.zip-volume"]
        ))

        list.append(ArchiveExtensionItem(
            id: "spk",
            ext: "spk",
            displayExt: ".spk",
            title: "Synology 群晖套件包",
            desc: "NAS 套件安装包（以 TAR 封装）",
            section: .volumes,
            utiIdentifiers: ["com.synology.spk-archive"]
        ))

        list.append(ArchiveExtensionItem(
            id: "xar",
            ext: "xar",
            displayExt: ".xar",
            title: "XAR 归档包",
            desc: "可扩展归档格式",
            section: .volumes,
            utiIdentifiers: ["com.apple.xar-archive"]
        ))

        // 4. 磁盘与容器镜像 (Containers)
        list.append(ArchiveExtensionItem(
            id: "dmg",
            ext: "dmg",
            displayExt: ".dmg",
            title: "Apple 磁盘映像",
            desc: "macOS 软件分发与只读磁盘包",
            section: .containers,
            utiIdentifiers: ["com.apple.disk-image", "com.apple.disk-image-udif", "public.disk-image"]
        ))

        list.append(ArchiveExtensionItem(
            id: "iso",
            ext: "iso",
            displayExt: ".iso",
            title: "光盘 ISO 映像",
            desc: "标准 CD / DVD 光盘文件系统映像",
            section: .containers,
            utiIdentifiers: ["public.iso-image"]
        ))

        list.append(ArchiveExtensionItem(
            id: "cab",
            ext: "cab",
            displayExt: ".cab",
            title: "Windows CAB 柜包",
            desc: "Windows 软件分发与安装文件柜",
            section: .containers,
            utiIdentifiers: ["com.microsoft.cab-archive"]
        ))

        return list
    }

    public func isAssociated(for id: String) -> Bool {
        isPureZipByID[id] ?? false
    }

    public func defaultAppName(for id: String) -> String {
        defaultAppNameByID[id] ?? "系统默认"
    }

    public func isUpdating(for id: String) -> Bool {
        updatingIDs.contains(id)
    }

    public func items(for section: ArchiveAssociationSection) -> [ArchiveExtensionItem] {
        items.filter { $0.section == section }
    }

    public func sectionStats(for section: ArchiveAssociationSection) -> (associated: Int, total: Int) {
        let secItems = items(for: section)
        let associated = secItems.filter { isAssociated(for: $0.id) }.count
        return (associated, secItems.count)
    }

    public func toggleSectionExpansion(_ section: ArchiveAssociationSection) {
        if expandedSections.contains(section.rawValue) {
            expandedSections.remove(section.rawValue)
        } else {
            expandedSections.insert(section.rawValue)
        }
    }

    public func refresh() {
        isRefreshing = true
        let allItems = self.items
        let targetBundleID = self.bundleIdentifier

        Task.detached(priority: .userInitiated) {
            var newNames: [String: String] = [:]
            var newIsPureZip: [String: Bool] = [:]
            var newCov: [String: AssociationCoverage] = [:]
            var pureZipCount = 0

            for item in allItems {
                let (appName, isPureZip) = Self.queryDefaultHandler(for: item, targetBundleID: targetBundleID)
                newNames[item.id] = appName
                newIsPureZip[item.id] = isPureZip
                newCov[item.id] = isPureZip ? .associated : .unassociated
                if isPureZip {
                    pureZipCount += 1
                }
            }

            let finalNames = newNames
            let finalIsPureZip = newIsPureZip
            let finalCov = newCov
            let finalCount = pureZipCount

            await MainActor.run {
                self.defaultAppNameByID = finalNames
                self.isPureZipByID = finalIsPureZip
                self.coverageByID = finalCov
                self.associatedExtensionCount = finalCount
                self.isRefreshing = false
            }
        }
    }

    public func setAsDefault(for item: ArchiveExtensionItem) {
        // 1. 乐观即时更新 (0ms 瞬时反馈，立即点亮图标与文字)
        self.isPureZipByID[item.id] = true
        self.defaultAppNameByID[item.id] = "PureZip"
        self.coverageByID[item.id] = .associated
        self.recalculateTotalCount()

        let targetURL = Self.pureZipAppURL

        Task.detached(priority: .userInitiated) {
            Self.assignTargetApp(targetURL, for: item)

            // 2. 适应系统确认弹窗的渐进延时核对 (检查系统是否已确认授权)
            for delay in [1.2, 2.5, 4.5] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                let (appName, isPureZip) = Self.queryDefaultHandler(for: item, targetBundleID: self.bundleIdentifier)
                await MainActor.run {
                    self.defaultAppNameByID[item.id] = appName
                    self.isPureZipByID[item.id] = isPureZip
                    self.coverageByID[item.id] = isPureZip ? .associated : .unassociated
                    self.recalculateTotalCount()
                }
            }
        }
    }

    public func restoreDefault(for item: ArchiveExtensionItem) {
        // 1. 乐观即时更新 (0ms 瞬时反馈)
        let fallbackName = (item.section == .containers) ? "磁盘映像装载程序" : "归档实用工具"
        self.isPureZipByID[item.id] = false
        self.defaultAppNameByID[item.id] = fallbackName
        self.coverageByID[item.id] = .unassociated
        self.recalculateTotalCount()

        Task.detached(priority: .userInitiated) {
            let isContainer = (item.section == .containers)
            let fallbackBID = isContainer ? "com.apple.DiskImageMounter" : "com.apple.archiveutility"
            let fallbackPath = isContainer ? "/System/Library/CoreServices/DiskImageMounter.app" : "/System/Library/CoreServices/Applications/Archive Utility.app"
            let fallbackURL = Self.appURL(forBundleID: fallbackBID, fallbackPath: fallbackPath)

            Self.assignTargetApp(fallbackURL, for: item)

            // 2. 渐进延时同步真实系统状态
            for delay in [1.2, 2.5, 4.5] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                let (appName, isPureZip) = Self.queryDefaultHandler(for: item, targetBundleID: self.bundleIdentifier)
                await MainActor.run {
                    self.defaultAppNameByID[item.id] = appName
                    self.isPureZipByID[item.id] = isPureZip
                    self.coverageByID[item.id] = isPureZip ? .associated : .unassociated
                    self.recalculateTotalCount()
                }
            }
        }
    }

    public func applyRecommendedAssociations() {
        isRefreshing = true
        let recommendedItems = items.filter { $0.isRecommended }
        let targetURL = Self.pureZipAppURL

        // 乐观即时更新
        for item in recommendedItems {
            self.isPureZipByID[item.id] = true
            self.defaultAppNameByID[item.id] = "PureZip"
            self.coverageByID[item.id] = .associated
        }
        self.recalculateTotalCount()

        Task.detached(priority: .userInitiated) {
            for item in recommendedItems {
                let (_, isPureZip) = Self.queryDefaultHandler(for: item, targetBundleID: self.bundleIdentifier)
                if !isPureZip {
                    Self.assignTargetApp(targetURL, for: item)
                }
            }

            for delay in [1.5, 3.0, 5.0] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    self.refresh()
                }
            }
        }
    }

    // Compatibility bridges
    public func coverage(for id: String) -> AssociationCoverage {
        coverageByID[id] ?? .unassociated
    }

    public func toggleAssociation(for id: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if isAssociated(for: id) {
            restoreDefault(for: item)
        } else {
            setAsDefault(for: item)
        }
    }

    public func setAssociated(_ enable: Bool, for desc: ArchiveFileAssociationDescriptor) {
        guard let item = items.first(where: { $0.id == desc.id }) else { return }
        if enable {
            setAsDefault(for: item)
        } else {
            restoreDefault(for: item)
        }
    }

    public func selectAllAssociations() {
        isRefreshing = true
        let allItems = self.items
        let targetURL = Self.pureZipAppURL

        Task.detached(priority: .userInitiated) {
            for item in allItems {
                Self.assignTargetApp(targetURL, for: item)
            }
            await MainActor.run {
                self.refresh()
            }
        }
    }

    public func deselectAllAssociations() {
        isRefreshing = true
        let allItems = self.items

        Task.detached(priority: .userInitiated) {
            for item in allItems {
                let isContainer = (item.section == .containers)
                let fallbackBID = isContainer ? "com.apple.DiskImageMounter" : "com.apple.archiveutility"
                let fallbackPath = isContainer ? "/System/Library/CoreServices/DiskImageMounter.app" : "/System/Library/CoreServices/Applications/Archive Utility.app"
                let fallbackURL = Self.appURL(forBundleID: fallbackBID, fallbackPath: fallbackPath)
                Self.assignTargetApp(fallbackURL, for: item)
            }
            await MainActor.run {
                self.refresh()
            }
        }
    }

    private func recalculateTotalCount() {
        associatedExtensionCount = isPureZipByID.values.filter { $0 }.count
    }

    // MARK: - Low-Level Helpers

    nonisolated private static func queryDefaultHandler(for item: ArchiveExtensionItem, targetBundleID: String) -> (displayName: String, isPureZip: Bool) {
        var resolvedURL: URL?

        // 1. Check via primary extension
        if let ut = UTType(filenameExtension: item.ext) {
            resolvedURL = NSWorkspace.shared.urlForApplication(toOpen: ut)
        }

        // 2. Check via primary UTI if not resolved
        if resolvedURL == nil, let firstUTI = item.utiIdentifiers.first, let ut = UTType(firstUTI) {
            resolvedURL = NSWorkspace.shared.urlForApplication(toOpen: ut)
        }

        guard let appURL = resolvedURL else {
            return ("系统默认", false)
        }

        let isPureZip = isTargetURL(appURL, targetBundleID: targetBundleID)

        if isPureZip {
            return ("PureZip", true)
        }

        // Extract human-friendly name
        let bundle = Bundle(url: appURL)
        let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle?.infoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle?.localizedInfoDictionary?["CFBundleName"] as? String ??
                   bundle?.infoDictionary?["CFBundleName"] as? String ??
                   appURL.deletingPathExtension().lastPathComponent

        return (name, false)
    }

    nonisolated private static var pureZipAppURL: URL {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return Bundle.main.bundleURL
        }
        if FileManager.default.fileExists(atPath: "/Applications/PureZip.app") {
            return URL(fileURLWithPath: "/Applications/PureZip.app")
        }
        return Bundle.main.bundleURL
    }

    nonisolated private static func appURL(forBundleID bundleID: String, fallbackPath: String) -> URL {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return URL(fileURLWithPath: fallbackPath)
    }

    nonisolated private static func collectUTTypes(for item: ArchiveExtensionItem) -> [UTType] {
        var types: [UTType] = []
        if let ut = UTType(filenameExtension: item.ext) {
            types.append(ut)
        }
        for uti in item.utiIdentifiers {
            if let ut = UTType(uti), !types.contains(ut) {
                types.append(ut)
            }
        }
        return types
    }

    nonisolated private static func assignTargetApp(_ targetURL: URL, for item: ArchiveExtensionItem) {
        let types = collectUTTypes(for: item)
        for ut in types {
            if let currentURL = NSWorkspace.shared.urlForApplication(toOpen: ut),
               currentURL.standardizedFileURL == targetURL.standardizedFileURL {
                continue
            }
            let sema = DispatchSemaphore(value: 0)
            NSWorkspace.shared.setDefaultApplication(at: targetURL, toOpen: ut) { _ in
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 0.3)
        }
    }

    nonisolated private static func isTargetURL(_ url: URL, targetBundleID: String) -> Bool {
        if let b = Bundle(url: url)?.bundleIdentifier?.lowercased() {
            if b == targetBundleID.lowercased() || b.contains("purezip") || b.contains("purezip") {
                return true
            }
        }
        let p = url.path.lowercased()
        return p.contains("purezip.app") || p.contains("purezip.app")
    }
}
