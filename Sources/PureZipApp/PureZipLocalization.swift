//
//  PureZipLocalization.swift
//  PureZip
//
//  Dynamic localization manager supporting System, Simplified Chinese, and English.
//

import Foundation
import AppKit
import SwiftUI
import ArchiveCore

@MainActor
public final class PureZipLocalization: ObservableObject {
    public static let shared = PureZipLocalization()

    @Published public var currentLanguage: String {
        didSet {
            PureZipPreferences.shared.appLanguage = currentLanguage
        }
    }

    private init() {
        self.currentLanguage = PureZipPreferences.shared.appLanguage
    }

    public var isEnglish: Bool {
        if currentLanguage == "en" { return true }
        if currentLanguage == "zh-Hans" { return false }
        // System default: check primary preferred language
        if let first = Locale.preferredLanguages.first {
            return first.hasPrefix("en")
        }
        return false
    }

    public func setLanguage(_ lang: String) {
        currentLanguage = lang
        objectWillChange.send()
    }

    public func localized(_ key: String) -> String {
        guard isEnglish else {
            return key
        }
        return Self.englishDictionary[key] ?? key
    }

    public static func t(_ key: String) -> String {
        PureZipLocalization.shared.localized(key)
    }

    public static func restartApplication() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - English Translation Catalog
    private static let englishDictionary: [String: String] = [
        // Tabs
        "通用": "General",
        "压缩": "Compression",
        "解压": "Extraction",
        "Pure Desk": "Pure Desk",
        "Pure Actions": "Pure Actions",
        "Pure Capsule": "Pure Capsule",
        "Pure Shelf": "Pure Shelf",
        "格式关联": "Associations",
        "高级": "Advanced",
        "关于": "About",

        // Sections
        "启动": "Startup",
        "外观": "Appearance",
        "语言": "Language",
        "浏览": "Browsing",
        "悬浮预览": "Hover Preview",
        "预设用途": "Preset Purpose",
        "压缩强度": "Compression Level",
        "分卷压缩": "Split Volumes",
        "常规解压": "General Extraction",
        "解压后操作": "Post-Extraction Action",
        "解压清理": "Extraction Cleanup",
        "编辑权限与自动保存": "Editing & Auto-Save",
        "上下文流操作": "Pure Actions",
        "外观与交互": "Appearance & Controls",
        "Pure Shelf 设置": "Pure Shelf Settings",
        "临时文件": "Temporary Files",
        "维护": "Maintenance",

        // General Tab
        "开机自动启动 PureZip": "Launch PureZip at login",
        "在系统登录时在后台启动 PureZip，加速归档打开与菜单栏常驻": "Launch PureZip in background at login for instant opening and menu bar shelf",
        "浅色": "Light",
        "深色": "Dark",
        "自动": "Auto",
        "应用语言": "App Language",
        "跟随系统语言，或为 PureZip 单独指定语言。": "Follow macOS system language, or specify for PureZip.",
        "跟随系统": "System Default",
        "简体中文": "Simplified Chinese",
        "English": "English",
        "默认浏览方式": "Default View Mode",
        "打开归档时默认采用的浏览视图布局。": "Default desk layout used when opening archives.",
        "图标": "Icons",
        "列表": "List",
        "分栏": "Columns",
        "显示辅助项目": "Show Auxiliary Items",
        "显示通常隐藏的系统辅助文件": "Show normally hidden macOS/Windows auxiliary files",
        "开启悬浮快捷预览": "Enable Hover Preview",
        "鼠标悬停在压缩包内文件上时，直接预览内容与元数据。": "Hover over archive items to instantly preview contents and metadata.",
        "无边框预览": "Frameless Preview",
        "图片、音视频等文件以极简悬浮视窗呈现，不显示属性边框。": "Images, audio, video and documents float without borders.",

        // Compression Tab
        "预设用途选择": "Choose Preset Purpose",
        "极速压缩": "Fastest",
        "标准压缩": "Standard",
        "深度压缩": "High",
        "极限压缩": "Maximum",
        "仅存储": "Store Only",
        "默认启用分卷压缩": "Enable Split Volumes by Default",

        // Extraction Tab
        "双击直接快速解压": "Extract on Double-Click",
        "在归档浏览器中双击文件时直接解压到默认目录": "Double-clicking files extracts directly to destination",
        "解压完成后自动关闭窗口": "Auto-Close Window After Extraction",
        "自动排除系统辅助文件": "Exclude System Auxiliary Files",
        "解压时自动清理 __MACOSX、.DS_Store 等临时与辅助文件": "Automatically strip __MACOSX, .DS_Store, and metadata files during extraction",
        "自动过滤 DMG 辅助项目": "Filter DMG Auxiliary Items",
        "打开或解压 DMG 时隐藏 .fseventsd、.Trashes 等磁盘辅助文件夹": "Hide .fseventsd, .Trashes and volume metadata when opening DMG images",

        // Pure Capsule Tab
        "允许在 Pure Capsule 浮窗中修改归档": "Allow Editing in Pure Capsule",
        "开启后支持拖入添加文件、右键重命名和删除，且变动将立即自动保存；关闭时 Pure Capsule 保持只读安全状态。": "Allows drag-and-drop file addition, rename, and deletion with immediate auto-save. When disabled, Pure Capsule remains read-only safe.",

        // Associations Tab
        "常用格式": "Common Formats",
        "压缩流": "Compression Streams",
        "磁盘与旧式容器": "Disk Images & Legacy",
        "软件包（谨慎）": "Packages (Cautious)",
        "推荐关联": "Recommended",
        "全部关联": "Associate All",
        "全部解除": "Deselect All",
        "已关联": "Associated",
        "部分关联": "Partial",
        "未关联": "Unassociated",

        // Advanced Tab
        "可清理的临时文件": "Cleanable Temporary Files",
        "清理": "Clean",
        "恢复所有设置": "Reset All Settings",
        "恢复默认值": "Reset to Defaults",
        "语言、通用、压缩、解压、Pure Actions 和 Pure Shelf 将恢复默认值": "All settings will be restored to their factory defaults",

        // About Tab
        "检查更新": "Check for Updates",
        "开源许可证": "Open Source Licenses",
        "访问 GitHub 仓库": "Visit GitHub Repository",
        "提交反馈与建议": "Submit Feedback & Issues",
        "轻量 · 极速 · 优雅的 macOS 原生全能归档管理工具": "Lightweight, ultra-fast and elegant native macOS archive manager",

        // Common Buttons
        "打开压缩包": "Open Archive",
        "创建压缩包": "Create Archive",
        "完成": "Done",
        "取消": "Cancel",
        "确定": "OK",
        "立即重启": "Restart Now"
    ]
}

public typealias L10n = PureZipLocalization
