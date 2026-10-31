import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Centralized, persistent application preferences for PureZip.
/// Backed by `UserDefaults` with App Group container support and live system synchronization.
@MainActor
public final class PureZipPreferences: ObservableObject {
    public static let shared = PureZipPreferences()

    private let defaults: UserDefaults

    // Keys
    private enum Key {
        static let autoLaunchAtLogin          = "PureZip.General.AutoLaunchAtLogin"
        static let appearanceMode             = "PureZip.General.AppearanceMode"
        static let appLanguage                = "PureZip.General.AppLanguage"
        static let dockIconVisibilityMode     = "PureZip.General.DockIconVisibilityMode"
        static let defaultViewMode            = "PureZip.General.DefaultViewMode"
        static let includeAuxiliary           = "PureZip.General.IncludeAuxiliary"
        static let hoverPreviewEnabled        = "PureZip.General.HoverPreviewEnabled"
        static let hoverPreviewFrameless      = "PureZip.General.HoverPreviewFrameless"

        static let compressionPurpose         = "PureZip.Compression.DefaultPurpose"
        static let compressionLevel           = "PureZip.Compression.DefaultLevel"
        static let defaultCreateSplitVolumes  = "PureZip.Compression.CreateSplitVolumes"

        static let quickExtractOnDoubleClick  = "PureZip.Extraction.QuickExtractOnDoubleClick"
        static let extractionPostAction       = "PureZip.Extraction.PostAction"
        static let autoCloseAfterExtraction   = "PureZip.Extraction.AutoClose"
        static let autoExcludeSystemAuxiliary = "PureZip.Extraction.ExcludeSystemAuxiliary"
        static let autoFilterDMGAuxiliary     = "PureZip.Extraction.FilterDMGAuxiliary"

        static let pureActionsQuickInstall      = "PureZip.PureActions.QuickInstall"
        static let pureActionsPostAction        = "PureZip.PureActions.PostAction"
        static let pureActionsAutoClose         = "PureZip.PureActions.AutoClose"
        static let pureActionsAllowedFormats    = "PureZip.PureActions.AllowedFormats"

        static let openWithCapsuleByDefault     = "PureZip.PureCapsule.OpenWithCapsuleByDefault"
        static let useLiquidGlass               = "PureZip.PureCapsule.UseLiquidGlass"
        static let useColorWindowButtons        = "PureZip.PureCapsule.UseColorWindowButtons"
        static let capsuleWindowAllowEditing    = "PureZip.PureCapsule.AllowEditing"

        static let deskVideoAutoPlay              = "PureZip.PureDesk.VideoAutoPlay"
        static let deskMediaAlwaysMute            = "PureZip.PureDesk.MediaAlwaysMute"
        static let deskUnsavedChangesAction       = "PureZip.PureDesk.UnsavedChangesAction"
        static let deskDuplicateNamingAction      = "PureZip.PureDesk.DuplicateNamingAction"
        static let deskConfirmLargeBatchOperations = "PureZip.PureDesk.ConfirmLargeBatchOperations"

        static let enablePureShelf              = "PureZip.PureShelf.Enabled"
        static let pureShelfColorIndex          = "PureZip.PureShelf.ColorIndex"
        static let pureShelfColorIntensity      = "PureZip.PureShelf.ColorIntensity"
        static let pureShelfAutoClear           = "PureZip.PureShelf.AutoClearAfterPackaging"
        static let pureShelfDefaultFormat       = "PureZip.PureShelf.DefaultFormat"
        static let pureShelfKeepPinned          = "PureZip.PureShelf.KeepWindowPinned"
        static let pureShelfShowBadge           = "PureZip.PureShelf.ShowCountBadge"
        static let pureShelfMainWindowEnabled    = "PureZip.PureShelf.MainWindowEnabled"
        static let pureShelfMainWindowDropAction = "PureZip.PureShelf.MainWindowDropAction"

        static let associationState           = "PureZip.Associations.State"
        static let autoCheckUpdates           = "PureZip.About.AutoCheckUpdates"
        static let preferencesSchemaVersion   = "PureZip.Internal.PreferencesSchemaVersion"
    }

    // MARK: - 1. 通用 (General)

    @Published public var autoLaunchAtLogin: Bool {
        didSet {
            defaults.set(autoLaunchAtLogin, forKey: Key.autoLaunchAtLogin)
            syncAutoLaunch()
        }
    }

    @Published public var appearanceMode: String {
        didSet {
            defaults.set(appearanceMode, forKey: Key.appearanceMode)
            syncAppearance()
        }
    }

    @Published public var appLanguage: String {
        didSet {
            defaults.set(appLanguage, forKey: Key.appLanguage)
            if appLanguage != "system" {
                defaults.set([appLanguage], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    /// Dock icon visibility mode: "never" (始终隐藏), "activeWindows" (仅在有窗口时显示), "always" (始终显示)
    @Published public var dockIconVisibilityMode: String {
        didSet {
            defaults.set(dockIconVisibilityMode, forKey: Key.dockIconVisibilityMode)
            NotificationCenter.default.post(name: Notification.Name("PureZipDockIconVisibilityModeChanged"), object: dockIconVisibilityMode)
        }
    }

    @Published public var defaultViewMode: String {
        didSet { defaults.set(defaultViewMode, forKey: Key.defaultViewMode) }
    }

    @Published public var includeAuxiliary: Bool {
        didSet { defaults.set(includeAuxiliary, forKey: Key.includeAuxiliary) }
    }

    @Published public var hoverPreviewEnabled: Bool {
        didSet { defaults.set(hoverPreviewEnabled, forKey: Key.hoverPreviewEnabled) }
    }

    @Published public var hoverPreviewFrameless: Bool {
        didSet { defaults.set(hoverPreviewFrameless, forKey: Key.hoverPreviewFrameless) }
    }

    // MARK: - 2. 压缩 (Compression)

    @Published public var compressionPurpose: ArchiveCreationPurpose {
        didSet { defaults.set(compressionPurpose.rawValue, forKey: Key.compressionPurpose) }
    }

    @Published public var compressionLevel: Int {
        didSet { defaults.set(compressionLevel, forKey: Key.compressionLevel) }
    }

    @Published public var defaultCreateSplitVolumes: Bool {
        didSet { defaults.set(defaultCreateSplitVolumes, forKey: Key.defaultCreateSplitVolumes) }
    }

    // MARK: - 3. 解压 (Extraction)

    @Published public var quickExtractOnDoubleClick: Bool {
        didSet { defaults.set(quickExtractOnDoubleClick, forKey: Key.quickExtractOnDoubleClick) }
    }

    @Published public var extractionPostAction: String {
        didSet { defaults.set(extractionPostAction, forKey: Key.extractionPostAction) }
    }

    @Published public var autoCloseAfterExtraction: Bool {
        didSet { defaults.set(autoCloseAfterExtraction, forKey: Key.autoCloseAfterExtraction) }
    }

    @Published public var autoExcludeSystemAuxiliary: Bool {
        didSet { defaults.set(autoExcludeSystemAuxiliary, forKey: Key.autoExcludeSystemAuxiliary) }
    }

    @Published public var autoFilterDMGAuxiliary: Bool {
        didSet { defaults.set(autoFilterDMGAuxiliary, forKey: Key.autoFilterDMGAuxiliary) }
    }

    // MARK: - 4. Pure Actions

    @Published public var pureActionsQuickInstall: Bool {
        didSet { defaults.set(pureActionsQuickInstall, forKey: Key.pureActionsQuickInstall) }
    }

    @Published public var pureActionsPostAction: String {
        didSet { defaults.set(pureActionsPostAction, forKey: Key.pureActionsPostAction) }
    }

    @Published public var pureActionsAutoClose: Bool {
        didSet { defaults.set(pureActionsAutoClose, forKey: Key.pureActionsAutoClose) }
    }

    @Published public var pureActionsAllowedFormats: Set<String> {
        didSet { defaults.set(Array(pureActionsAllowedFormats), forKey: Key.pureActionsAllowedFormats) }
    }

    // MARK: - 5. Pure Capsule

    @Published public var openWithCapsuleByDefault: Bool {
        didSet { defaults.set(openWithCapsuleByDefault, forKey: Key.openWithCapsuleByDefault) }
    }

    @Published public var useLiquidGlass: Bool {
        didSet { defaults.set(useLiquidGlass, forKey: Key.useLiquidGlass) }
    }

    @Published public var useColorWindowButtons: Bool {
        didSet { defaults.set(useColorWindowButtons, forKey: Key.useColorWindowButtons) }
    }

    @Published public var capsuleWindowAllowEditing: Bool {
        didSet { defaults.set(capsuleWindowAllowEditing, forKey: Key.capsuleWindowAllowEditing) }
    }

    // MARK: - 5.5. Pure Desk

    @Published public var deskVideoAutoPlay: Bool {
        didSet { defaults.set(deskVideoAutoPlay, forKey: Key.deskVideoAutoPlay) }
    }

    @Published public var deskMediaAlwaysMute: Bool {
        didSet { defaults.set(deskMediaAlwaysMute, forKey: Key.deskMediaAlwaysMute) }
    }

    @Published public var deskUnsavedChangesAction: String {
        didSet { defaults.set(deskUnsavedChangesAction, forKey: Key.deskUnsavedChangesAction) }
    }

    @Published public var deskDuplicateNamingAction: String {
        didSet { defaults.set(deskDuplicateNamingAction, forKey: Key.deskDuplicateNamingAction) }
    }

    @Published public var deskConfirmLargeBatchOperations: Bool {
        didSet { defaults.set(deskConfirmLargeBatchOperations, forKey: Key.deskConfirmLargeBatchOperations) }
    }

    @Published public var pureShelfMainWindowEnabled: Bool {
        didSet { defaults.set(pureShelfMainWindowEnabled, forKey: Key.pureShelfMainWindowEnabled) }
    }

    @Published public var pureShelfMainWindowDropAction: String {
        didSet { defaults.set(pureShelfMainWindowDropAction, forKey: Key.pureShelfMainWindowDropAction) }
    }

    // MARK: - 6. Pure Shelf 随航搁板 (Pure Shelf)

    @Published public var enablePureShelf: Bool {
        didSet { defaults.set(enablePureShelf, forKey: Key.enablePureShelf) }
    }

    @Published public var pureShelfColorIndex: Int {
        didSet { defaults.set(pureShelfColorIndex, forKey: Key.pureShelfColorIndex) }
    }

    @Published public var pureShelfColorIntensity: Double {
        didSet { defaults.set(pureShelfColorIntensity, forKey: Key.pureShelfColorIntensity) }
    }

    @Published public var pureShelfAutoClearAfterPackaging: Bool {
        didSet { defaults.set(pureShelfAutoClearAfterPackaging, forKey: Key.pureShelfAutoClear) }
    }

    @Published public var pureShelfDefaultFormat: String {
        didSet { defaults.set(pureShelfDefaultFormat, forKey: Key.pureShelfDefaultFormat) }
    }

    @Published public var pureShelfKeepWindowPinned: Bool {
        didSet { defaults.set(pureShelfKeepWindowPinned, forKey: Key.pureShelfKeepPinned) }
    }

    @Published public var pureShelfShowCountBadge: Bool {
        didSet { defaults.set(pureShelfShowCountBadge, forKey: Key.pureShelfShowBadge) }
    }

    // MARK: - 7. 格式关联 (Associations)

    @Published public var associationState: [String: Bool] {
        didSet { defaults.set(associationState, forKey: Key.associationState) }
    }

    // MARK: - 8. 高级与维护 (Advanced)

    @Published public var tempFileSizeString: String = "0 KB"
    @Published public var xpcIsolationEnabled: Bool = true
    @Published public var sqliteWALCacheSizeMB: Int = 64

    // MARK: - 9. 关于 (About)

    @Published public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Key.autoCheckUpdates) }
    }

    @Published public var updateStatusText: String = "尚未检查更新"

    // MARK: - Initialization

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Migrate preferences across versions if necessary
        Self.migratePreferencesIfNeeded(defaults: defaults)

        // 1. General
        self.autoLaunchAtLogin = defaults.object(forKey: Key.autoLaunchAtLogin) as? Bool ?? true
        self.appearanceMode = defaults.string(forKey: Key.appearanceMode) ?? "auto"
        self.appLanguage = defaults.string(forKey: Key.appLanguage) ?? "system"
        self.dockIconVisibilityMode = defaults.string(forKey: Key.dockIconVisibilityMode) ?? "never"
        self.defaultViewMode = defaults.string(forKey: Key.defaultViewMode) ?? "list"
        self.includeAuxiliary = defaults.object(forKey: Key.includeAuxiliary) as? Bool ?? false
        self.hoverPreviewEnabled = defaults.object(forKey: Key.hoverPreviewEnabled) as? Bool ?? true
        self.hoverPreviewFrameless = defaults.object(forKey: Key.hoverPreviewFrameless) as? Bool ?? true

        // 2. Compression
        let rawPurpose = defaults.string(forKey: Key.compressionPurpose) ?? "general"
        self.compressionPurpose = ArchiveCreationPurpose(rawValue: rawPurpose) ?? .general
        self.compressionLevel = defaults.object(forKey: Key.compressionLevel) as? Int ?? 2
        self.defaultCreateSplitVolumes = defaults.bool(forKey: Key.defaultCreateSplitVolumes)

        // 3. Extraction
        self.quickExtractOnDoubleClick = defaults.bool(forKey: Key.quickExtractOnDoubleClick)
        self.extractionPostAction = defaults.string(forKey: Key.extractionPostAction) ?? "每次均询问"
        self.autoCloseAfterExtraction = defaults.bool(forKey: Key.autoCloseAfterExtraction)
        self.autoExcludeSystemAuxiliary = defaults.object(forKey: Key.autoExcludeSystemAuxiliary) as? Bool ?? true
        self.autoFilterDMGAuxiliary = defaults.object(forKey: Key.autoFilterDMGAuxiliary) as? Bool ?? true

        // 4. Pure Actions
        self.pureActionsQuickInstall = defaults.object(forKey: Key.pureActionsQuickInstall) as? Bool ?? true
        self.pureActionsPostAction = defaults.string(forKey: Key.pureActionsPostAction) ?? "每次均询问"
        self.pureActionsAutoClose = defaults.object(forKey: Key.pureActionsAutoClose) as? Bool ?? true
        if let storedFormats = defaults.stringArray(forKey: Key.pureActionsAllowedFormats) {
            self.pureActionsAllowedFormats = Set(storedFormats)
        } else {
            self.pureActionsAllowedFormats = [
                "PDF", "纯文本", "Markdown", "RTF", "CSV", "Word", "Excel", "PowerPoint", "EPUB",
                "JPEG", "PNG", "GIF", "WebP", "HEIF / HEIC", "TIFF", "BMP", "SVG",
                "MP3", "M4A / AAC", "WAV", "FLAC", "OGG",
                "MP4 / M4V", "MOV", "MKV", "WebM", "AVI",
                "HTML", "XML", "JSON", "YAML", "Plist"
            ]
        }

        // 5. Pure Capsule
        self.openWithCapsuleByDefault = defaults.object(forKey: Key.openWithCapsuleByDefault) as? Bool ?? true
        self.useLiquidGlass = defaults.object(forKey: Key.useLiquidGlass) as? Bool ?? true
        self.useColorWindowButtons = defaults.bool(forKey: Key.useColorWindowButtons)
        self.capsuleWindowAllowEditing = defaults.object(forKey: Key.capsuleWindowAllowEditing) as? Bool ?? false

        // 5.5. Pure Desk
        self.deskVideoAutoPlay = defaults.object(forKey: Key.deskVideoAutoPlay) as? Bool ?? true
        self.deskMediaAlwaysMute = defaults.object(forKey: Key.deskMediaAlwaysMute) as? Bool ?? true
        self.deskUnsavedChangesAction = defaults.string(forKey: Key.deskUnsavedChangesAction) ?? "ask"
        self.deskDuplicateNamingAction = defaults.string(forKey: Key.deskDuplicateNamingAction) ?? "autoRename"
        self.deskConfirmLargeBatchOperations = defaults.object(forKey: Key.deskConfirmLargeBatchOperations) as? Bool ?? true

        // 6. Pure Shelf
        self.enablePureShelf = defaults.object(forKey: Key.enablePureShelf) as? Bool ?? true
        self.pureShelfColorIndex = defaults.integer(forKey: Key.pureShelfColorIndex)
        let intensity = defaults.double(forKey: Key.pureShelfColorIntensity)
        self.pureShelfColorIntensity = intensity > 0 ? intensity : 35.0
        self.pureShelfAutoClearAfterPackaging = defaults.object(forKey: Key.pureShelfAutoClear) as? Bool ?? true
        self.pureShelfDefaultFormat = defaults.string(forKey: Key.pureShelfDefaultFormat) ?? "zip"
        self.pureShelfKeepWindowPinned = defaults.object(forKey: Key.pureShelfKeepPinned) as? Bool ?? false
        self.pureShelfShowCountBadge = defaults.object(forKey: Key.pureShelfShowBadge) as? Bool ?? true
        self.pureShelfMainWindowEnabled = defaults.object(forKey: Key.pureShelfMainWindowEnabled) as? Bool ?? true
        self.pureShelfMainWindowDropAction = defaults.string(forKey: Key.pureShelfMainWindowDropAction) ?? "stageInShelf"

        // 7. Associations
        if let dict = defaults.dictionary(forKey: Key.associationState) as? [String: Bool] {
            self.associationState = dict
        } else {
            self.associationState = [
                "zip": false, "7z": true, "split": false, "rar": true,
                "cbr": false, "tar": true, "gzip": false, "bzip2": false, "xz": true
            ]
        }

        // 9. About
        self.autoCheckUpdates = defaults.object(forKey: Key.autoCheckUpdates) as? Bool ?? true

        // Initial system sync
        syncAppearance()
        refreshTemporaryDiskUsage()
    }

    // MARK: - Preferences Schema Migration

    public static let currentPreferencesSchemaVersion: Int = 1

    /// Automatically migrates preferences across version upgrades, preserving user choices
    /// and safely handling deprecated or restructured configuration keys.
    public static func migratePreferencesIfNeeded(defaults: UserDefaults) {
        let storedVersion = defaults.integer(forKey: Key.preferencesSchemaVersion)
        guard storedVersion < currentPreferencesSchemaVersion else { return }

        // Migration step: Version 0 -> 1
        if storedVersion < 1 {
            // e.g. Legacy Dock icon boolean migrated to tripartite dockIconVisibilityMode
            if let legacyDockBool = defaults.object(forKey: "PureZip.General.ShowDockIcon") as? Bool {
                if defaults.object(forKey: Key.dockIconVisibilityMode) == nil {
                    defaults.set(legacyDockBool ? "always" : "never", forKey: Key.dockIconVisibilityMode)
                }
                defaults.removeObject(forKey: "PureZip.General.ShowDockIcon")
            }

            // Prune any legacy / abandoned preference keys from early experimental builds
            let deprecatedKeys: [String] = [
                "PureZip.PureCapsule.LegacyAlphaStyle",
                "PureZip.General.LegacyToolbarMode"
            ]
            for key in deprecatedKeys {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(currentPreferencesSchemaVersion, forKey: Key.preferencesSchemaVersion)
    }

    // MARK: - System Synchronizations

    #if canImport(SwiftUI)
    public var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default:
            #if canImport(AppKit)
            // 跟随系统：读取实时的系统外观（NSApp.appearance 为 nil 时 effectiveAppearance 即系统外观）
            return Self.systemIsDark ? .dark : .light
            #else
            return nil
            #endif
        }
    }
    #endif

    #if canImport(AppKit)
    /// 当前系统是否为深色模式（实时）
    public static var systemIsDark: Bool {
        if let app = NSApp {
            return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return (UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased().contains("dark")) ?? false
    }

    private var systemAppearanceObservation: NSKeyValueObservation?
    #endif

    /// 跟随系统时返回 nil，让 AppKit 自动随系统切换
    public var effectiveNSAppearance: NSAppearance? {
        #if canImport(AppKit)
        switch appearanceMode {
        case "light":
            return NSAppearance(named: .aqua)
        case "dark":
            return NSAppearance(named: .darkAqua)
        default:
            return nil
        }
        #else
        return nil
        #endif
    }

    /// 监听系统外观变化（仅注册一次），在“跟随系统”模式下刷新 SwiftUI 视图
    private func observeSystemAppearanceIfNeeded() {
        #if canImport(AppKit)
        guard systemAppearanceObservation == nil, let app = NSApp else { return }
        systemAppearanceObservation = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.appearanceMode != "light", self.appearanceMode != "dark" else { return }
                self.objectWillChange.send()
                NotificationCenter.default.post(name: NSNotification.Name("PureZipAppearanceDidChange"), object: nil)
            }
        }
        #endif
    }

    public func syncAppearance() {
        #if canImport(AppKit)
        observeSystemAppearanceIfNeeded()
        let appAppearance = effectiveNSAppearance
        NSApp?.appearance = appAppearance
        for window in NSApp?.windows ?? [] {
            window.appearance = appAppearance
        }
        NotificationCenter.default.post(name: NSNotification.Name("PureZipAppearanceDidChange"), object: appAppearance)
        #endif
    }

    public func syncAutoLaunch() {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if autoLaunchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Not running from bundled app or permission denied in development
            }
        }
        #endif
    }

    // MARK: - Disk Temporary Files Cleanup

    public func refreshTemporaryDiskUsage() {
        var totalBytes: Int64 = 0
        let fm = FileManager.default

        let candidateDirs = [
            NSTemporaryDirectory(),
            (NSTemporaryDirectory() as NSString).appendingPathComponent("purezip"),
            (NSTemporaryDirectory() as NSString).appendingPathComponent("PureZip"),
            FileManager.default.temporaryDirectory.path
        ]

        let searchTokens = ["extract", "lease", "PureZip", "PureZip", "purezip", "Stage", "DMG"]

        for dir in candidateDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            if let items = try? fm.contentsOfDirectory(atPath: dir) {
                for item in items {
                    if searchTokens.contains(where: { item.contains($0) }) {
                        let full = (dir as NSString).appendingPathComponent(item)
                        if let attrs = try? fm.attributesOfItem(atPath: full),
                           let size = attrs[.size] as? Int64 {
                            totalBytes += size
                        }
                    }
                }
            }
        }

        if totalBytes > 1024 * 1024 {
            tempFileSizeString = String(format: "%.1f MB", Double(totalBytes) / (1024 * 1024))
        } else if totalBytes > 0 {
            tempFileSizeString = "\(totalBytes / 1024) KB"
        } else {
            tempFileSizeString = "0 KB"
        }
    }

    public func cleanTemporaryFiles() {
        let fm = FileManager.default
        let candidateDirs = [
            NSTemporaryDirectory(),
            (NSTemporaryDirectory() as NSString).appendingPathComponent("purezip"),
            (NSTemporaryDirectory() as NSString).appendingPathComponent("PureZip"),
            FileManager.default.temporaryDirectory.path
        ]

        let searchTokens = ["extract", "lease", "PureZip", "PureZip", "purezip", "Stage", "DMG"]

        for dir in candidateDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            if let items = try? fm.contentsOfDirectory(atPath: dir) {
                for item in items {
                    if searchTokens.contains(where: { item.contains($0) }) {
                        let full = (dir as NSString).appendingPathComponent(item)
                        try? fm.removeItem(atPath: full)
                    }
                }
            }
        }
        tempFileSizeString = "0 KB"
    }

    // MARK: - Factory Reset

    public func resetAllSettings() {
        let domain = Bundle.main.bundleIdentifier ?? "com.minato.purezip"
        defaults.removePersistentDomain(forName: domain)

        autoLaunchAtLogin = true
        appearanceMode = "auto"
        appLanguage = "system"
        defaultViewMode = "list"
        includeAuxiliary = false
        hoverPreviewEnabled = true
        hoverPreviewFrameless = true

        compressionPurpose = .general
        compressionLevel = 2
        defaultCreateSplitVolumes = false

        quickExtractOnDoubleClick = false
        extractionPostAction = "每次均询问"
        autoCloseAfterExtraction = false
        autoExcludeSystemAuxiliary = true
        autoFilterDMGAuxiliary = true

        pureActionsQuickInstall = true
        pureActionsPostAction = "每次均询问"
        pureActionsAutoClose = true
        pureActionsAllowedFormats = [
            "PDF", "纯文本", "Markdown", "RTF", "CSV", "Word", "Excel", "PowerPoint", "EPUB",
            "JPEG", "PNG", "GIF", "WebP", "HEIF / HEIC", "TIFF", "BMP", "SVG",
            "MP3", "M4A / AAC", "WAV", "FLAC", "OGG",
            "MP4 / M4V", "MOV", "MKV", "WebM", "AVI",
            "HTML", "XML", "JSON", "YAML", "Plist"
        ]

        openWithCapsuleByDefault = true
        useLiquidGlass = true
        useColorWindowButtons = false
        capsuleWindowAllowEditing = false

        enablePureShelf = true
        pureShelfColorIndex = 0
        pureShelfColorIntensity = 35.0
        pureShelfAutoClearAfterPackaging = true
        pureShelfDefaultFormat = "zip"
        pureShelfKeepWindowPinned = false
        pureShelfShowCountBadge = true
        pureShelfMainWindowEnabled = true
        pureShelfMainWindowDropAction = "stageInShelf"

        // Note: Association in LaunchServices/Finder is preserved on preferences reset
        autoCheckUpdates = true
        updateStatusText = "尚未检查更新"

        syncAppearance()
        cleanTemporaryFiles()
    }
}
