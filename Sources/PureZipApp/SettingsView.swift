import AppKit
import SwiftUI
import Combine
import ArchiveCore
import ArchiveEngines

// MARK: - Settings View Model

@MainActor
public final class SettingsViewModel: ObservableObject {
    public let prefs = PureZipPreferences.shared
    @Published public var selectedTab: SettingsView.SettingsTab = .compression

    // 1. 通用 (General)
    public var autoLaunchAtLogin: Bool {
        get { prefs.autoLaunchAtLogin }
        set { prefs.autoLaunchAtLogin = newValue; objectWillChange.send() }
    }
    public var appearanceMode: String {
        get { prefs.appearanceMode }
        set { prefs.appearanceMode = newValue; objectWillChange.send() }
    }
    @Published public var showLanguageRestartNotice: Bool = false

    public var appLanguage: String {
        get { prefs.appLanguage }
        set {
            prefs.appLanguage = newValue
            PureZipLocalization.shared.setLanguage(newValue)
            showLanguageRestartNotice = true
            objectWillChange.send()
        }
    }
    public var dockIconVisibilityMode: String {
        get { prefs.dockIconVisibilityMode }
        set { prefs.dockIconVisibilityMode = newValue; objectWillChange.send() }
    }
    public var selectedDefaultViewMode: DeskViewMode {
        get {
            switch prefs.defaultViewMode.lowercased() {
            case "icons", "图标": return .icons
            case "columns", "分栏": return .columns
            default: return .list
            }
        }
        set {
            prefs.defaultViewMode = newValue.rawValue
            objectWillChange.send()
        }
    }
    public var defaultViewMode: String {
        get { prefs.defaultViewMode }
        set { prefs.defaultViewMode = newValue; objectWillChange.send() }
    }
    public var includeAuxiliary: Bool {
        get { prefs.includeAuxiliary }
        set { prefs.includeAuxiliary = newValue; objectWillChange.send() }
    }
    public var hoverPreviewEnabled: Bool {
        get { prefs.hoverPreviewEnabled }
        set { prefs.hoverPreviewEnabled = newValue; objectWillChange.send() }
    }
    public var hoverPreviewFrameless: Bool {
        get { prefs.hoverPreviewFrameless }
        set { prefs.hoverPreviewFrameless = newValue; objectWillChange.send() }
    }

    // 2. 压缩 (Compression)
    public var compressionPurpose: ArchiveCreationPurpose {
        get { prefs.compressionPurpose }
        set { prefs.compressionPurpose = newValue; objectWillChange.send() }
    }
    public var compressionLevel: Int {
        get { prefs.compressionLevel }
        set { prefs.compressionLevel = newValue; objectWillChange.send() }
    }
    public var defaultCreateSplitVolumes: Bool {
        get { prefs.defaultCreateSplitVolumes }
        set { prefs.defaultCreateSplitVolumes = newValue; objectWillChange.send() }
    }

    // 3. 解压 (Extraction)
    public var quickExtractOnDoubleClick: Bool {
        get { prefs.quickExtractOnDoubleClick }
        set { prefs.quickExtractOnDoubleClick = newValue; objectWillChange.send() }
    }
    public var extractionPostAction: String {
        get { prefs.extractionPostAction }
        set { prefs.extractionPostAction = newValue; objectWillChange.send() }
    }
    public var autoCloseAfterExtraction: Bool {
        get { prefs.autoCloseAfterExtraction }
        set { prefs.autoCloseAfterExtraction = newValue; objectWillChange.send() }
    }
    public var autoExcludeSystemAuxiliary: Bool {
        get { prefs.autoExcludeSystemAuxiliary }
        set { prefs.autoExcludeSystemAuxiliary = newValue; objectWillChange.send() }
    }
    public var autoFilterDMGAuxiliary: Bool {
        get { prefs.autoFilterDMGAuxiliary }
        set { prefs.autoFilterDMGAuxiliary = newValue; objectWillChange.send() }
    }

    // 4. Pure Actions
    public var pureActionsQuickInstall: Bool {
        get { prefs.pureActionsQuickInstall }
        set { prefs.pureActionsQuickInstall = newValue; objectWillChange.send() }
    }
    public var pureActionsPostAction: String {
        get { prefs.pureActionsPostAction }
        set { prefs.pureActionsPostAction = newValue; objectWillChange.send() }
    }
    public var pureActionsAutoClose: Bool {
        get { prefs.pureActionsAutoClose }
        set { prefs.pureActionsAutoClose = newValue; objectWillChange.send() }
    }

    public static let allPureActionsFormats: [String] = [
        // 文档 (9)
        "PDF", "纯文本", "Markdown", "RTF", "CSV", "Word", "Excel", "PowerPoint", "EPUB",
        // 图像 (8)
        "JPEG", "PNG", "GIF", "WebP", "HEIF / HEIC", "TIFF", "BMP", "SVG",
        // 音频 (5)
        "MP3", "M4A / AAC", "WAV", "FLAC", "OGG",
        // 视频 (5)
        "MP4 / M4V", "MOV", "MKV", "WebM", "AVI",
        // 数据与网页 (5)
        "HTML", "XML", "JSON", "YAML", "Plist"
    ]
    public var pureActionsAllowedFormats: Set<String> {
        get { prefs.pureActionsAllowedFormats }
        set { prefs.pureActionsAllowedFormats = newValue; objectWillChange.send() }
    }

    // 5. Pure Capsule
    public var openWithCapsuleByDefault: Bool {
        get { prefs.openWithCapsuleByDefault }
        set { prefs.openWithCapsuleByDefault = newValue; objectWillChange.send() }
    }
    public var useLiquidGlass: Bool {
        get { prefs.useLiquidGlass }
        set { prefs.useLiquidGlass = newValue; objectWillChange.send() }
    }
    public var useColorWindowButtons: Bool {
        get { prefs.useColorWindowButtons }
        set { prefs.useColorWindowButtons = newValue; objectWillChange.send() }
    }
    public var capsuleWindowAllowEditing: Bool {
        get { prefs.capsuleWindowAllowEditing }
        set { prefs.capsuleWindowAllowEditing = newValue; objectWillChange.send() }
    }

    // 5.5. Pure Desk
    public var deskVideoAutoPlay: Bool {
        get { prefs.deskVideoAutoPlay }
        set { prefs.deskVideoAutoPlay = newValue; objectWillChange.send() }
    }
    public var deskMediaAlwaysMute: Bool {
        get { prefs.deskMediaAlwaysMute }
        set { prefs.deskMediaAlwaysMute = newValue; objectWillChange.send() }
    }
    public var deskUnsavedChangesAction: String {
        get { prefs.deskUnsavedChangesAction }
        set { prefs.deskUnsavedChangesAction = newValue; objectWillChange.send() }
    }
    public var deskDuplicateNamingAction: String {
        get { prefs.deskDuplicateNamingAction }
        set { prefs.deskDuplicateNamingAction = newValue; objectWillChange.send() }
    }
    public var deskConfirmLargeBatchOperations: Bool {
        get { prefs.deskConfirmLargeBatchOperations }
        set { prefs.deskConfirmLargeBatchOperations = newValue; objectWillChange.send() }
    }

    // 6. Pure Shelf 随航搁板 (Pure Shelf)
    public var pureShelfMainWindowEnabled: Bool {
        get { prefs.pureShelfMainWindowEnabled }
        set { prefs.pureShelfMainWindowEnabled = newValue; objectWillChange.send() }
    }
    public var pureShelfMainWindowDropAction: String {
        get { prefs.pureShelfMainWindowDropAction }
        set { prefs.pureShelfMainWindowDropAction = newValue; objectWillChange.send() }
    }
    public var enablePureShelf: Bool {
        get { prefs.enablePureShelf }
        set { prefs.enablePureShelf = newValue; objectWillChange.send() }
    }
    public var pureShelfColorIndex: Int {
        get { prefs.pureShelfColorIndex }
        set { prefs.pureShelfColorIndex = newValue; objectWillChange.send() }
    }
    public var pureShelfColorIntensity: Double {
        get { prefs.pureShelfColorIntensity }
        set { prefs.pureShelfColorIntensity = newValue; objectWillChange.send() }
    }
    public var pureShelfAutoClearAfterPackaging: Bool {
        get { prefs.pureShelfAutoClearAfterPackaging }
        set { prefs.pureShelfAutoClearAfterPackaging = newValue; objectWillChange.send() }
    }
    public var pureShelfDefaultFormat: String {
        get { prefs.pureShelfDefaultFormat }
        set { prefs.pureShelfDefaultFormat = newValue; objectWillChange.send() }
    }
    public var pureShelfKeepWindowPinned: Bool {
        get { prefs.pureShelfKeepWindowPinned }
        set { prefs.pureShelfKeepWindowPinned = newValue; objectWillChange.send() }
    }
    public var pureShelfShowCountBadge: Bool {
        get { prefs.pureShelfShowCountBadge }
        set { prefs.pureShelfShowCountBadge = newValue; objectWillChange.send() }
    }

    // 7. 格式关联 (Associations) - Real LaunchServices Catalog
    private var cancellables = Set<AnyCancellable>()
    public var associationStore: ArchiveAssociationStore {
        ArchiveAssociationStore.shared
    }
    public var totalAssociatedCount: Int {
        associationStore.associatedExtensionCount
    }
    public var associationState: [String: Bool] {
        get {
            var map: [String: Bool] = [:]
            for d in associationStore.descriptors {
                map[d.id] = (associationStore.coverage(for: d.id) == .associated)
            }
            return map
        }
        set {
            objectWillChange.send()
        }
    }

    // 8. 高级 (Advanced)
    public var tempFileSizeString: String {
        prefs.tempFileSizeString
    }
    public var isCleaningTemp: Bool = false
    public var xpcIsolationEnabled: Bool {
        get { prefs.xpcIsolationEnabled }
        set { prefs.xpcIsolationEnabled = newValue; objectWillChange.send() }
    }
    public var sqliteWALCacheSizeMB: Int {
        get { prefs.sqliteWALCacheSizeMB }
        set { prefs.sqliteWALCacheSizeMB = newValue; objectWillChange.send() }
    }
    public var maxWorkerThreads: Int = ProcessInfo.processInfo.activeProcessorCount

    // 9. 关于 (About)
    public var updateManager: PureZipUpdateManager {
        PureZipUpdateManager.shared
    }
    public var autoCheckUpdates: Bool {
        get { prefs.autoCheckUpdates }
        set { prefs.autoCheckUpdates = newValue; objectWillChange.send() }
    }
    public var updateStatusText: String {
        get { updateManager.statusMessage }
        set { updateManager.statusMessage = newValue; objectWillChange.send() }
    }
    public var isCheckingUpdates: Bool {
        updateManager.isChecking
    }
    @Published public var showOpenSourceLicenses: Bool = false

    public static let pureShelfPalette: [Color] = [
        Color(red: 0.05, green: 0.48, blue: 0.98), // Tech Ocean Blue
        Color(red: 0.18, green: 0.65, blue: 0.95), // Sky Blue
        Color(red: 0.91, green: 0.20, blue: 0.48), // Pink
        Color(red: 0.92, green: 0.34, blue: 0.34), // Red
        Color(red: 0.95, green: 0.60, blue: 0.29), // Orange
        Color(red: 0.95, green: 0.79, blue: 0.30), // Yellow
        Color(red: 0.25, green: 0.68, blue: 0.38), // Green
        Color(red: 0.55, green: 0.55, blue: 0.58)  // Gray
    ]

    public init() {
        ArchiveAssociationStore.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        PureZipUpdateManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        PureZipLocalization.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public func selectAllPureActionsFormats() {
        pureActionsAllowedFormats = Set(Self.allPureActionsFormats)
    }

    public func deselectAllPureActionsFormats() {
        pureActionsAllowedFormats = []
    }

    public func togglePureActionsFormat(_ format: String) {
        var set = pureActionsAllowedFormats
        if set.contains(format) {
            set.remove(format)
        } else {
            set.insert(format)
        }
        pureActionsAllowedFormats = set
    }

    public func resetCompressionDefaults() {
        compressionPurpose = .general
        compressionLevel = 2
        defaultCreateSplitVolumes = false
    }

    public func toggleAssociation(_ key: String) {
        associationStore.toggleAssociation(for: key)
    }

    public func selectAllAssociations() {
        associationStore.selectAllAssociations()
    }

    public func deselectAllAssociations() {
        associationStore.deselectAllAssociations()
    }

    public func applyRecommendedAssociations() {
        associationStore.applyRecommendedAssociations()
    }

    public func refreshAssociations() {
        associationStore.refresh()
    }

    public func cleanTemporaryFiles() {
        prefs.cleanTemporaryFiles()
        objectWillChange.send()
    }

    public func checkForUpdates() {
        updateManager.checkForUpdates(userInitiated: true)
    }

    public func resetAllSettings() {
        prefs.resetAllSettings()
        objectWillChange.send()
    }
}

// MARK: - Main Settings View

public struct SettingsView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @ObservedObject var model = SettingsViewModel()
    @Environment(\.colorScheme) private var colorScheme

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general       = "通用"
        case compression   = "压缩"
        case extraction    = "解压"
        case pureDesk      = "Pure Desk"
        case pureCapsule   = "Pure Capsule"
        case pureShelf     = "Pure Shelf"
        case pureActions   = "Pure Actions"
        case associations  = "格式关联"
        case advanced      = "高级"
        case about         = "关于"

        public var id: String { rawValue }

        public var systemImage: String {
            switch self {
            case .general:      return "gearshape"
            case .compression:  return "arrow.down.to.line.compact"
            case .extraction:   return "arrow.up.to.line.compact"
            case .pureDesk:     return "macwindow"
            case .pureCapsule:  return "pip"
            case .pureShelf:    return "shippingbox.fill"
            case .pureActions:  return "bolt.fill"
            case .associations: return "link"
            case .advanced:     return "slider.horizontal.3"
            case .about:        return "info.circle"
            }
        }
    }

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            sidebarView
                .frame(width: 215)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Right Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch model.selectedTab {
                    case .general:
                        generalSettingsContent
                    case .compression:
                        compressionSettingsContent
                    case .extraction:
                        extractionSettingsContent
                    case .pureDesk:
                        pureDeskSettingsContent
                    case .pureCapsule:
                        pureCapsuleSettingsContent
                    case .pureShelf:
                        pureShelfSettingsContent
                    case .pureActions:
                        pureActionsSettingsContent
                    case .associations:
                        associationsSettingsContent
                    case .advanced:
                        advancedSettingsContent
                    case .about:
                        aboutSettingsContent
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 840, height: 640)
        .background(
            Button("") {
                session.closeSettings()
            }
            .keyboardShortcut("w", modifiers: .command)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
        )
        .onAppear {
            model.selectedTab = session.selectedSettingsTab
        }
        .preferredColorScheme(model.prefs.preferredColorScheme)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Logo (Positioned cleanly below macOS native window traffic lights)
            HStack(spacing: 10) {
                PureZipLogoSymbolView(size: 26)
                Text("PureZip")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 46)
            .padding(.bottom, 16)

            // Sidebar Tab Items
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        HStack(spacing: 12) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(L10n.t(tab.rawValue))
                                .font(.system(size: 13, weight: model.selectedTab == tab ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(model.selectedTab == tab ? (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(model.selectedTab == tab ? Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .foregroundStyle(model.selectedTab == tab ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color.primary)
                        .onTapGesture {
                            model.selectedTab = tab
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer()
        }
    }

    // MARK: - 1. 通用 (General)

    private var generalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("通用")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            // 启动
            VStack(alignment: .leading, spacing: 8) {
                Text("启动")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("开机自动启动 PureZip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: $model.autoLaunchAtLogin)
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // Dock 栏显示
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("程序坞与后台"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("程序坞（Dock）图标"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("选择 PureZip 在程序坞中的常驻行为。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.dockIconVisibilityMode) {
                            Text(L10n.t("始终隐藏（默认）")).tag("never")
                            Text(L10n.t("仅在有窗口时显示")).tag("activeWindows")
                            Text(L10n.t("始终显示")).tag("always")
                        }
                        .frame(width: 170)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }

            // 外观
            VStack(alignment: .leading, spacing: 8) {
                Text("外观")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    AppearanceCard(title: "浅色", isSelected: model.appearanceMode == "light", imageName: "sun.max.fill") {
                        model.appearanceMode = "light"
                    }
                    AppearanceCard(title: "深色", isSelected: model.appearanceMode == "dark", imageName: "moon.fill") {
                        model.appearanceMode = "dark"
                    }
                    AppearanceCard(title: "自动", isSelected: model.appearanceMode == "auto", imageName: "circle.righthalf.filled") {
                        model.appearanceMode = "auto"
                    }
                }
            }

            // 语言
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("语言"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("应用语言"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("跟随系统语言，或为 PureZip 单独指定语言。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.appLanguage) {
                            Text(L10n.t("跟随系统")).tag("system")
                            Text("简体中文").tag("zh-Hans")
                            Text("English").tag("en")
                        }
                        .frame(width: 130)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    if model.showLanguageRestartNotice {
                        Divider()
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                            Text(L10n.t("提示：重启应用以完全应用新语言"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.t("立即重启")) {
                                L10n.restartApplication()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.05, green: 0.48, blue: 0.98))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.08))
                    }
                }
                .cornerRadius(10)
            }

            // 浏览
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("浏览"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("默认浏览方式"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("打开归档时默认采用的浏览视图布局。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(DeskViewMode.allCases) { mode in
                                let isSelected = (model.selectedDefaultViewMode == mode)
                                Button {
                                    model.selectedDefaultViewMode = mode
                                    session.viewMode = mode
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: mode.systemImage)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(L10n.t(mode.rawValue))
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color.clear)
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }
                        .padding(3)
                        .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90))
                        .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("显示辅助项目")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("显示通常隐藏的系统辅助文件")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.includeAuxiliary },
                            set: { newVal in
                                model.includeAuxiliary = newVal
                                session.includeAuxiliary = newVal
                                try? session.refreshDisplayedEntries()
                            }
                        ))
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("悬浮预览")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("停留 1 秒，预览图片与文档")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.hoverPreviewEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    if model.hoverPreviewEnabled {
                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("无外框预览 (纯内容悬浮)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("直接贴合图片与文档外形展示，去除四周卡片与多余边框")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(white: 0.55))
                            }
                            Spacer()
                            Toggle("", isOn: $model.hoverPreviewFrameless)
                                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                }
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 2. 压缩 (Compression)

    private var compressionSettingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("压缩")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            // 默认用途与压缩强度
            VStack(alignment: .leading, spacing: 10) {
                Text("默认用途与压缩强度")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                // 5 Cards
                HStack(spacing: 10) {
                    let purposes: [ArchiveCreationPurpose] = [.general, .windows, .mac, .linux, .smallest]
                    ForEach(purposes) { purpose in
                        Button {
                            model.compressionPurpose = purpose
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: purpose.systemImage)
                                    .font(.system(size: 22))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 28)

                                Text(purpose.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)

                                Text(purpose.subtitle)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .foregroundStyle(model.compressionPurpose == purpose ? Color.white.opacity(0.85) : Color.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(model.compressionPurpose == purpose ? Color(red: 0.45, green: 0.28, blue: 0.95) : (colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.94)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(model.compressionPurpose == purpose ? Color.clear : (colorScheme == .dark ? Color(white: 0.22) : Color.black.opacity(0.08)), lineWidth: 1)
                            )
                            .foregroundStyle(model.compressionPurpose == purpose ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 场景核心优势与技术特性卡片 (Scenario Advantages & Technical Overview)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: model.compressionPurpose.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))

                        Text("\(model.compressionPurpose.title) · 模式说明")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(model.compressionPurpose.formatBadge)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.15))
                            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                            .clipShape(Capsule())
                    }

                    Divider()

                    // Advantage Items
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.compressionPurpose.advantagesList) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color(red: 0.05, green: 0.48, blue: 0.98))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    Text(item.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.25), lineWidth: 1)
                )

                // 默认压缩强度 Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("默认压缩强度")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(model.compressionPurpose.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.18, green: 0.60, blue: 1.0))
                    }

                    Text("修改仅应用于当前选中的用途")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)

                    // Stepper Track
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            let stepWidth = geo.size.width / 4.0
                            ZStack(alignment: .leading) {
                                // Inactive track
                                Capsule()
                                    .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
                                    .frame(height: 6)

                                // Active track
                                Capsule()
                                    .fill(Color(red: 0.05, green: 0.48, blue: 0.98))
                                    .frame(width: max(8, CGFloat(model.compressionLevel) * stepWidth), height: 6)

                                // 5 Dots
                                ForEach(0..<5) { idx in
                                    Circle()
                                        .fill(idx <= model.compressionLevel ? Color.white : Color(white: 0.45))
                                        .frame(width: 5, height: 5)
                                        .offset(x: CGFloat(idx) * stepWidth - 2.5)
                                }

                                // Interactive Thumb
                                Circle()
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .overlay(Circle().stroke(Color(red: 0.05, green: 0.48, blue: 0.98), lineWidth: 3))
                                    .frame(width: 18, height: 18)
                                    .offset(x: CGFloat(model.compressionLevel) * stepWidth - 9)
                            }
                            .frame(height: 18)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        let chosen = Int(round(val.location.x / stepWidth))
                                        model.compressionLevel = min(max(chosen, 0), 4)
                                    }
                            )
                        }
                        .frame(height: 18)

                        HStack {
                            Text("更快")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            VStack(spacing: 2) {
                                Text(levelName(for: model.compressionLevel))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(red: 0.18, green: 0.60, blue: 1.0))
                                Text(levelDescription(for: model.compressionLevel))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.55))
                            }
                            Spacer()
                            Text("更小")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // 分卷压缩
            VStack(alignment: .leading, spacing: 8) {
                Text("分卷压缩")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("默认创建分卷压缩包")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("新建压缩包时自动启用分卷")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    Spacer()
                    Toggle("", isOn: $model.defaultCreateSplitVolumes)
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // 恢复默认压缩设置 (Bottom Right)
            HStack {
                Spacer()
                Button {
                    model.resetCompressionDefaults()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                        Text("恢复默认压缩设置")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(colorScheme == .dark ? Color(white: 0.3) : Color.black.opacity(0.12), lineWidth: 1))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func levelName(for level: Int) -> String {
        switch level {
        case 0: return "最快"
        case 1: return "较快"
        case 2: return "均衡"
        case 3: return "偏小"
        default: return "最小"
        }
    }

    private func levelDescription(for level: Int) -> String {
        switch level {
        case 0: return "以极快速度存储，压缩率较低"
        case 1: return "速度优先，适合大型日志"
        case 2: return "兼顾速度和大小"
        case 3: return "较好压缩比，适合日常传输"
        default: return "最大化压缩比，耗时较长"
        }
    }

    // MARK: - 3. 解压 (Extraction)

    private var extractionSettingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("解压")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            // 打开压缩包
            VStack(alignment: .leading, spacing: 8) {
                Text("打开压缩包")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("双击时快速解压")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("开启此选项后，双击压缩包会将它立刻解压到所在文件夹，跳过浏览步骤。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    Spacer()
                    Toggle("", isOn: $model.quickExtractOnDoubleClick)
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // 全部解压
            VStack(alignment: .leading, spacing: 8) {
                Text("全部解压")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("如何处理压缩包")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("全部解压完成后，选择保留或移入废纸篓")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.extractionPostAction) {
                            Text("每次均询问").tag("每次均询问")
                            Text("保留压缩包").tag("保留压缩包")
                            Text("移入废纸篓").tag("移入废纸篓")
                        }
                        .frame(width: 130)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动关闭压缩包")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("全部解压完成并保留压缩包后，自动关闭窗口")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.autoCloseAfterExtraction)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }

            // 内容过滤
            VStack(alignment: .leading, spacing: 8) {
                Text("内容过滤")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动排除系统辅助文件")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("过滤 macOS、Windows 生成的辅助文件")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.autoExcludeSystemAuxiliary)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动过滤 DMG 安装辅助文件")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("过滤隐藏布局文件与 Applications 替身")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.autoFilterDMGAuxiliary)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)

                Text("明确选中的项目、用户隐藏文件和应用包内容都会保留。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - 4. Pure Actions

    private var pureActionsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Pure Actions")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            // 应用安装
            VStack(alignment: .leading, spacing: 8) {
                Text("应用安装")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("快捷安装")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("安装时移除下载来源标记，可能减少 macOS 的安全提示。仅在信任应用来源时开启。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.pureActionsQuickInstall)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("如何处理压缩包")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("应用安装完成后，选择保留或移入废纸篓")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.pureActionsPostAction) {
                            Text("每次均询问").tag("每次均询问")
                            Text("保留压缩包").tag("保留压缩包")
                            Text("移入废纸篓").tag("移入废纸篓")
                        }
                        .frame(width: 130)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动关闭压缩包")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("应用安装完成并保留压缩包后，自动关闭窗口")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.pureActionsAutoClose)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }

            // 打开文件
            VStack(alignment: .leading, spacing: 8) {
                Text("打开文件")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("允许打开的文件格式")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("为所选格式提供“打开文件”操作")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Text("\(model.pureActionsAllowedFormats.count) / 32")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        Button {
                            model.selectAllPureActionsFormats()
                        } label: {
                            Text("选择全部")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(red: 0.85, green: 0.70, blue: 0.25))
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.deselectAllPureActionsFormats()
                        } label: {
                            Text("全部取消")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Format Categories
                    pureActionsFormatCategory(title: "文档", items: ["PDF", "纯文本", "Markdown", "RTF", "CSV", "Word", "Excel", "PowerPoint", "EPUB"])
                    pureActionsFormatCategory(title: "图像", items: ["JPEG", "PNG", "GIF", "WebP", "HEIF / HEIC", "TIFF", "BMP", "SVG"])
                    pureActionsFormatCategory(title: "音频", items: ["MP3", "M4A / AAC", "WAV", "FLAC", "OGG"])
                    pureActionsFormatCategory(title: "视频", items: ["MP4 / M4V", "MOV", "MKV", "WebM", "AVI"])
                    pureActionsFormatCategory(title: "数据与网页", items: ["HTML", "XML", "JSON", "YAML", "Plist"])
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
    }

    private func pureActionsFormatCategory(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), alignment: .leading)], spacing: 10) {
                ForEach(items, id: \.self) { item in
                    let isChecked = model.pureActionsAllowedFormats.contains(item)
                    Button {
                        model.togglePureActionsFormat(item)
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isChecked ? Color(red: 0.90, green: 0.72, blue: 0.15) : (colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.86)))
                                    .frame(width: 16, height: 16)

                                if isChecked {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }

                            Text(item)
                                .font(.system(size: 12))
                                .foregroundStyle(isChecked ? Color.primary : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 3.5. Pure Desk

    private var pureDeskSettingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Pure Desk")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            // 1. 默认布局与视图
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("默认布局与视图"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("默认浏览视图"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("进入工作区时默认采用的归档浏览布局。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(DeskViewMode.allCases) { mode in
                                let isSelected = (model.selectedDefaultViewMode == mode)
                                Button {
                                    model.selectedDefaultViewMode = mode
                                    session.viewMode = mode
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: mode.systemImage)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(L10n.t(mode.rawValue))
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color.clear)
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }
                        .padding(3)
                        .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90))
                        .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }

            // 2. 右侧媒体播放与预览
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("右侧媒体播放与预览"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    // 视频预览播放行为
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("视频预览播放行为"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("在右侧属性栏选中视频文件时的初始行为。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.deskVideoAutoPlay) {
                            Text("默认静音自动开始播放").tag(true)
                            Text("仅展示封面等待手动点击").tag(false)
                        }
                        .frame(width: 200)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // 音视频是否默认静音
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("音视频是否默认静音"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("预览音视频文件时是否始终以静音状态启动。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.deskMediaAlwaysMute) {
                            Text("始终静音 (推荐)").tag(true)
                            Text("不静音 (开启声音)").tag(false)
                        }
                        .frame(width: 170)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }

            // 3. 编辑与保存安全
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("编辑与保存安全"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    // 关闭窗口时有未保存修改的处理方式
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("关闭窗口时存在未保存修改"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("在工作区进行了增删改但未按 ⌘S 时关闭窗口的动作。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.deskUnsavedChangesAction) {
                            Text("每次均询问 (默认)").tag("ask")
                            Text("自动保存并退出").tag("autoSave")
                            Text("放弃修改").tag("discard")
                        }
                        .frame(width: 170)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // 同名文件拖入处理
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("同名文件拖入处理"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("向工作区拖入与现有条目同名文件时的默认处理方式。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.deskDuplicateNamingAction) {
                            Text("自动重命名为副本").tag("autoRename")
                            Text("询问覆盖或保留双方").tag("ask")
                        }
                        .frame(width: 180)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // 提交大批量增删保存时是否提示确认
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("大批量增删保存时二次确认"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("当单次保存的修改项较多时，弹窗提示并确认，防止误操作破坏归档。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.deskConfirmLargeBatchOperations)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 4. Pure Capsule

    private var pureCapsuleSettingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Pure Capsule")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text("打开方式与外观")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    // Row 1
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("默认用 Pure Capsule 打开")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("从 Finder 打开压缩包时优先使用 Pure Capsule 胶囊浮窗")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.openWithCapsuleByDefault)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Row 2
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("使用 Liquid Glass 材质")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("关闭后使用经典毛玻璃材质，即时应用于 Pure Capsule 浮窗")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.useLiquidGlass)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Row 3
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("使用彩色窗口控制按钮")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("关闭后按钮恢复未着色外观，置顶时仍保留淡蓝色按钮和圆环")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.useColorWindowButtons)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }

            // 编辑权限与自动保存
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("编辑权限与自动保存"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("允许在 Pure Capsule 浮窗中修改归档"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(L10n.t("开启后支持拖入添加文件、右键重命名和删除，且变动将立即自动保存；关闭时 Pure Capsule 保持只读安全状态。"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.capsuleWindowAllowEditing)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 5. Pure Shelf

    private var pureShelfSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pure Shelf")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            // Centered Live Pure Shelf Preview (Adaptive Day/Night Theme)
            VStack {
                // Outer window frame of Pure Shelf
                VStack(spacing: 0) {
                    // Titlebar of Pure Shelf
                    HStack(spacing: 8) {
                        PureZipLogoSymbolView(size: 18)
                        Text("PureZip")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Pure Shelf")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white.opacity(0.85))
                            .clipShape(Capsule())
                            .foregroundStyle(.primary)

                        Spacer()

                        // Pin button
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(red: 0.88, green: 0.60, blue: 0.05))
                            .frame(width: 20, height: 20)
                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                            .clipShape(Circle())

                        // Close button
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))

                    // Pure Shelf Body Area
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                            )

                        // Hollow Inbox Icon with Down Arrow
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 46, weight: .light))
                                .foregroundStyle(colorScheme == .dark ? Color(white: 0.40) : Color(white: 0.62))
                            Text("可从访达拖入文件暂存")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(height: 160)
                }
                .frame(width: 260)
                .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 10, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            // 第一部分：Pure Shelf 菜单栏托盘
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                    Text("Pure Shelf 菜单栏托盘")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("启用菜单栏托盘")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("在屏幕右上角常驻菜单栏图标，支持随时随地向托盘拖入文件。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.enablePureShelf)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("默认打包格式")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("从菜单栏托盘一键打包时所采用的归档格式。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.pureShelfDefaultFormat) {
                            Text("ZIP 格式 (.zip)").tag("zip")
                            Text("7-Zip 格式 (.7z)").tag("7z")
                            Text("Tarball 格式 (.tar.gz)").tag("tar.gz")
                        }
                        .frame(width: 160)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("打包后自动清空")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("归档文件创建成功后，自动从托盘中移除已暂存的项目。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.pureShelfAutoClearAfterPackaging)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("保持托盘浮窗置顶")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("打开托盘时默认固定图钉，切换到其他应用时不自动关闭。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.pureShelfKeepWindowPinned)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("显示暂存数量角标")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("在菜单栏图标旁实时标注当前 Pure Shelf 中的文件数量。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.pureShelfShowCountBadge)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }

            // 第二部分：Pure Shelf 主窗口
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                    Text("Pure Shelf 主窗口")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 1) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("未打开归档时作为主工作台")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("启动应用或关闭归档后，主窗口展示暂存起航台，支持拖放收集与新建。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $model.pureShelfMainWindowEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("主窗口文件拖入动作")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("向主窗口拖入非压缩包文件时的默认处理方式。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                        }
                        Spacer()
                        Picker("", selection: $model.pureShelfMainWindowDropAction) {
                            Text("加入 Pure Shelf 等待打包").tag("stageInShelf")
                            Text("直接弹出新建归档").tag("createNewArchive")
                        }
                        .frame(width: 160)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 6. 格式关联 (Associations) - Real LaunchServices Catalog

    private var associationsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("格式关联")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                Text("按格式分类精确设置双击默认打开方式，避免批量修改引发频繁系统弹窗")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // 关联状态 Card
            VStack(alignment: .leading, spacing: 8) {
                Text("关联状态")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(associationStatusColor)
                            .frame(width: 8, height: 8)
                        Text(associationStatusTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.92))
                    .clipShape(Capsule())

                    Spacer()

                    Button {
                        model.refreshAssociations()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(model.associationStore.isRefreshing ? .degrees(360) : .zero)
                                .animation(model.associationStore.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.associationStore.isRefreshing)
                            Text("刷新")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.92))
                        .clipShape(Capsule())
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.applyRecommendedAssociations()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("一键应用常用推荐")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.05, green: 0.48, blue: 0.98))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // 分类可折叠列表
            ForEach(ArchiveAssociationSection.allCases) { section in
                associationSectionCard(section)
            }

            // 底部特别说明
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("提示：macOS 系统对更改默认应用程序有安全保护机制。单项点击“设为默认”时仅触发该格式的一次确认；未修改的格式不会重复弹窗。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private func associationSectionCard(_ section: ArchiveAssociationSection) -> some View {
        let isExpanded = model.associationStore.expandedSections.contains(section.rawValue)
        let stats = model.associationStore.sectionStats(for: section)
        let sectionItems = model.associationStore.items(for: section)

        return VStack(alignment: .leading, spacing: 0) {
            // Header Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.associationStore.toggleSectionExpansion(section)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: section.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                        .frame(width: 28, height: 28)
                        .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(section.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Stats badge
                    Text("\(stats.associated) / \(stats.total)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(stats.associated == stats.total ? Color.green.opacity(0.15) : (colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90)))
                        .foregroundStyle(stats.associated == stats.total ? Color.green : Color.secondary)
                        .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Item List
            if isExpanded {
                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(sectionItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 54)
                        }
                        extensionItemRow(item)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color(white: 0.20) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func extensionItemRow(_ item: ArchiveExtensionItem) -> some View {
        let isPureZip = model.associationStore.isAssociated(for: item.id)
        let appName = model.associationStore.defaultAppName(for: item.id)
        let isUpdating = model.associationStore.isUpdating(for: item.id)

        return HStack(spacing: 12) {
            // Extension Tag Badge
            Text("." + item.ext)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isPureZip ? Color(red: 0.05, green: 0.48, blue: 0.98) : .secondary)
                .frame(width: 44, height: 26)
                .background(isPureZip ? Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.14) : (colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92)))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(item.displayExt)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(isPureZip ? Color.green : Color.gray.opacity(0.7))
                        .frame(width: 6, height: 6)

                    Text("当前默认: \(appName)")
                        .font(.system(size: 11))
                        .foregroundStyle(isPureZip ? Color.green : Color.secondary)
                }
            }

            Spacer()

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 64, height: 26)
            } else if isPureZip {
                Button {
                    model.associationStore.restoreDefault(for: item)
                } label: {
                    Text("恢复默认")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    model.associationStore.setAsDefault(for: item)
                } label: {
                    Text("设为默认")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4.5)
                        .background(Color(red: 0.05, green: 0.48, blue: 0.98))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var associationStatusTitle: String {
        let count = model.associationStore.associatedExtensionCount
        let total = model.associationStore.items.count
        if count == 0 {
            return "未关联"
        } else if count >= total {
            return "已关联全部 \(total) 个格式"
        } else {
            return "已关联 \(count) / \(total) 个格式"
        }
    }

    private var associationStatusColor: Color {
        let count = model.associationStore.associatedExtensionCount
        let total = model.associationStore.items.count
        if count == 0 {
            return Color.gray
        } else if count < total / 2 {
            return Color.orange
        } else {
            return Color.green
        }
    }

    // MARK: - 7. 高级 (Advanced)

    private var advancedSettingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("高级")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            // 临时文件
            VStack(alignment: .leading, spacing: 8) {
                Text("临时文件")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("可清理的临时文件")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(model.tempFileSizeString)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    Spacer()
                    Button {
                        model.cleanTemporaryFiles()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("清理")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(colorScheme == .dark ? Color(white: 0.3) : Color.black.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // 维护
            VStack(alignment: .leading, spacing: 8) {
                Text("维护")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("恢复所有设置")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("语言、通用、压缩、解压、Pure Actions 和 Pure Shelf 将恢复默认值")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    Spacer()
                    Button {
                        model.resetAllSettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text("恢复默认值")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.95, green: 0.12, blue: 0.35))
                        .clipShape(Capsule())
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 8. 关于 (About) - GitHub Releases & Project Center

    private var aboutSettingsContent: some View {
        VStack(spacing: 22) {
            // App Icon & App Name Header (Centered)
            VStack(spacing: 10) {
                PureZipLogoSymbolView(size: 78)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 10, x: 0, y: 5)

                VStack(spacing: 4) {
                    Text("PureZip")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("轻量 · 极速 · 优雅的 macOS 原生全能归档管理工具")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)

            // New Version Available Banner (Conditional)
            if model.updateManager.hasNewVersion, let release = model.updateManager.latestRelease {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("发现新版本")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.primary)

                                Text(release.tagName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.05, green: 0.48, blue: 0.98))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }

                            if !release.name.isEmpty && release.name != release.tagName {
                                Text(release.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }

                    if !release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(release.body.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.6))
                            .lineLimit(4)
                            .lineSpacing(2)
                            .padding(10)
                            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
                            .cornerRadius(6)
                    }

                    HStack(spacing: 12) {
                        Button {
                            if let url = release.downloadURL {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.open(release.htmlURL)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("立即前往下载")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.05, green: 0.48, blue: 0.98), Color(red: 0.02, green: 0.36, blue: 0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            NSWorkspace.shared.open(release.htmlURL)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                Text("查看发布说明")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92))
                            .clipShape(Capsule())
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.4), lineWidth: 1.5))
                .cornerRadius(12)
            }

            // Version & Auto Update Card
            VStack(spacing: 1) {
                // Row 1: 当前版本
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("当前版本")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(model.updateManager.systemArchString)
                                .font(.system(size: 11))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.88))
                                .cornerRadius(4)
                                .foregroundStyle(.secondary)
                        }

                        Text(model.updateManager.versionDisplayString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            if model.isCheckingUpdates {
                                ProgressView()
                                    .controlSize(.mini)
                            } else if model.updateManager.hasNewVersion {
                                Circle().fill(Color.orange).frame(width: 7, height: 7)
                            } else if model.updateManager.checkError != nil {
                                Circle().fill(Color.red).frame(width: 7, height: 7)
                            } else if model.updateStatusText.contains("已是最新版本") {
                                Circle().fill(Color.green).frame(width: 7, height: 7)
                            }
                            Text(model.updateStatusText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        model.checkForUpdates()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(model.isCheckingUpdates ? 360 : 0))
                                .animation(model.isCheckingUpdates ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: model.isCheckingUpdates)
                            Text(model.isCheckingUpdates ? "正在检查..." : "检查更新")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(colorScheme == .dark ? Color(white: 0.3) : Color.black.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isCheckingUpdates)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Row 2: 自动检查更新
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动检查更新")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("在应用启动时自动检测 GitHub Releases 是否有新版本。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    Spacer()
                    Toggle("", isOn: $model.autoCheckUpdates)
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.05, green: 0.48, blue: 0.98)))
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .cornerRadius(12)

            // GitHub Community & Open Source Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "curlybraces.square.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 1.0))

                    Text("开源社区")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("GitHub")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.88))
                        .cornerRadius(4)
                        .foregroundStyle(.primary)
                }

                Text("PureZip 为完全免费的开源工具，源代码与发行包均托管于 GitHub。欢迎 Star 支持、提交 Issue 反馈或参与共建！")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.60))
                    .lineSpacing(2)

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(PureZipUpdateManager.repoWebURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))
                            Text("GitHub 仓库")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.48, blue: 0.98), Color(red: 0.02, green: 0.36, blue: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(PureZipUpdateManager.issuesWebURL)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "ant.fill")
                                .font(.system(size: 11))
                            Text("提交反馈 (Issue)")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(colorScheme == .dark ? Color(white: 0.3) : Color.black.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(PureZipUpdateManager.releasesWebURL)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 11))
                            Text("Releases 列表")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(colorScheme == .dark ? Color(white: 0.3) : Color.black.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        let alert = NSAlert()
                        alert.messageText = "开源组件许可说明"
                        alert.informativeText = """
                        PureZip 基于以下优秀的开源技术构建：

                        • 7-Zip & LZMA SDK (7zz)
                          许可协议：GNU LGPL 2.1 与 unRAR 授权说明
                          Copyright (C) 1999-2024 Igor Pavlov.

                        • SQLite 3
                          许可协议：Public Domain (公有领域)
                          用于实现毫秒级 SQLite WAL 目录树虚拟索引。

                        • Apple Swift & SwiftUI
                          许可协议：Apache License 2.0 with Runtime Library Exception.

                        • libz & libarchive / BSDTar
                          许可协议：zlib license / Simplified BSD License.
                        """
                        alert.addButton(withTitle: "确定")
                        alert.runModal()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 11))
                            Text("组件许可")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.92))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(colorScheme == .dark ? Color(white: 0.3) : Color.black.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            // Technical Specs Card
            HStack(spacing: 16) {
                Label("7-Zip (LZMA2)", systemImage: "cpu")
                Text("•").foregroundStyle(.tertiary)
                Label("SQLite 3 (WAL)", systemImage: "internaldrive")
                Text("•").foregroundStyle(.tertiary)
                Label("SwiftUI 原生架构", systemImage: "macwindow")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helper Views

/// Appearance Selection Card
struct AppearanceCard: View {
    let title: String
    let isSelected: Bool
    let imageName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 72)

                    Image(systemName: imageName)
                        .font(.system(size: 28))
                        .foregroundStyle(isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color(white: 0.6))
                }

                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98) : .primary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Restored previous iconic shipping box / archive box icon
public struct PureZipLogoSymbolView: View {
    public let size: CGFloat

    public init(size: CGFloat = 28) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.96), Color(white: 0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.12), radius: size * 0.08, x: 0, y: size * 0.04)
                .frame(width: size, height: size)

            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.52))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.75, blue: 1.0),
                            Color(red: 0.05, green: 0.45, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

/// Standardized two-line brand badge: larger logo on left, "Pure" on line 1, sublabel ("Capsule", "Shelf", etc.) on line 2,
/// with the logo icon sized to match the full height of the two text lines.
public struct PureZipBrandBadgeView: View {
    public let sublabel: String
    public let logoSize: CGFloat

    public init(_ sublabel: String, logoSize: CGFloat = 28) {
        self.sublabel = sublabel
        self.logoSize = logoSize
    }

    public var body: some View {
        HStack(spacing: 7) {
            PureZipLogoSymbolView(size: logoSize)

            VStack(alignment: .leading, spacing: 0) {
                Text("Pure")
                    .font(.system(size: logoSize * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(sublabel)
                    .font(.system(size: logoSize * 0.35, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(height: logoSize, alignment: .center)
        }
    }
}
