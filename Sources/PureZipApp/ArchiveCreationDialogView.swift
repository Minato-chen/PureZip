import AppKit
import SwiftUI
import ArchiveCore
import ArchiveEngines
import PureZipFinderSupport

/// Observable model managing archive creation configuration state.
@MainActor
public final class ArchiveCreationViewModel: ObservableObject {
    public let sources: [URL]
    @Published public var selectedPurpose: ArchiveCreationPurpose = .windows
    @Published public var selectedFormat: ArchiveFormat = .zip
    @Published public var compressionStrength: ArchiveCompressionStrength = .standard
    @Published public var sliderStep: Int = 2 // 0: 更快, 1: 偏快, 2: 均衡, 3: 偏小, 4: 更小

    // Split Volume & Advanced
    @Published public var isAdvancedExpanded: Bool = false
    @Published public var selectedVolumeSize: ArchiveCreationVolumeSize = .none
    @Published public var customVolumeMB: String = "100"

    // Encryption
    @Published public var enableEncryption: Bool = false
    @Published public var password: String = ""
    @Published public var encryptHeaders: Bool = true
    @Published public var isShowingPasswordPlain: Bool = false

    // Destination & Naming
    @Published public var destinationDirectory: URL
    @Published public var archiveStem: String
    @Published public var compatibilityIssues: [ArchiveCreationPurpose.WindowsCompatibilityIssue] = []
    @Published public var customizedFilenames: [UUID: String] = [:]
    @Published public var isShowingCompatibilitySheet: Bool = false

    public init(sources: [URL]) {
        self.sources = sources
        self.destinationDirectory = sources.first?.deletingLastPathComponent() ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let baseStem = FinderArchiveNaming.suggestedStem(for: sources)
        self.archiveStem = baseStem.isEmpty ? "未命名压缩包.zip" : (baseStem.hasSuffix(".zip") ? baseStem : "\(baseStem).zip")
        let defaultPurpose = PureZipPreferences.shared.compressionPurpose
        self.selectedPurpose = defaultPurpose
        self.selectedFormat = defaultPurpose.defaultFormat
        if PureZipPreferences.shared.defaultCreateSplitVolumes {
            self.selectedVolumeSize = .mb100
        }
        applyPurposePreset(defaultPurpose)
        runCompatibilityCheck()
    }

    public func applyPurposePreset(_ purpose: ArchiveCreationPurpose) {
        selectedPurpose = purpose
        selectedFormat = purpose.defaultFormat
        let defaultLevel = PureZipPreferences.shared.compressionLevel
        switch purpose {
        case .general:
            selectedFormat = .zip
            updateStrengthFromStep(defaultLevel)
        case .windows:
            selectedFormat = .zip
            updateStrengthFromStep(defaultLevel)
            runCompatibilityCheck()
        case .mac:
            selectedFormat = .zip
            updateStrengthFromStep(defaultLevel)
        case .linux:
            selectedFormat = .tar
            updateStrengthFromStep(defaultLevel)
        case .smallest:
            selectedFormat = .sevenZip
            compressionStrength = .maximum
            sliderStep = 4
        case .custom:
            updateStrengthFromStep(defaultLevel)
        }
        syncFilenameExtension()
    }

    public func updateStrengthFromStep(_ step: Int) {
        sliderStep = step
        switch step {
        case 0, 1:
            compressionStrength = .fastest
        case 2:
            compressionStrength = .standard
        case 3, 4:
            compressionStrength = .maximum
        default:
            compressionStrength = .standard
        }
    }

    public func syncFilenameExtension() {
        let (rawStem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(archiveStem)
        let ext = selectedFormat == .sevenZip ? "7z" : selectedFormat.rawValue
        archiveStem = "\(rawStem).\(ext)"
    }

    public func runCompatibilityCheck() {
        let paths = ArchiveCreationPurpose.enumerateRelativePaths(for: sources)
        compatibilityIssues = ArchiveCreationPurpose.validateWindowsCompatibility(paths: paths)
        for issue in compatibilityIssues {
            if customizedFilenames[issue.id] == nil {
                customizedFilenames[issue.id] = issue.suggestedFilename
            }
        }
    }

    public func restoreAllSuggestions() {
        for issue in compatibilityIssues {
            customizedFilenames[issue.id] = issue.suggestedFilename
        }
    }

    public func buildPathRemappings() -> [String: String] {
        var map: [String: String] = [:]
        for issue in compatibilityIssues {
            let orig = issue.originalPath
            let newFilename = customizedFilenames[issue.id]?.trimmingCharacters(in: .whitespaces) ?? issue.suggestedFilename
            guard !newFilename.isEmpty else { continue }
            let parent = (orig as NSString).deletingLastPathComponent
            let newPath = parent.isEmpty ? newFilename : "\(parent)/\(newFilename)"
            if newPath != orig {
                map[orig] = newPath
            }
        }
        return map
    }

    public func chooseDestinationFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择存储位置"
        if panel.runModal() == .OK, let url = panel.url {
            destinationDirectory = url
        }
    }

    public var strengthDisplayName: String {
        switch sliderStep {
        case 0: return "极速"
        case 1: return "较快"
        case 2: return "均衡"
        case 3: return "高压缩"
        case 4: return "极限"
        default: return "均衡"
        }
    }
}

/// Interactive archive creation configuration dialog.
public struct ArchiveCreationDialogView: View {
    @ObservedObject var model: ArchiveCreationViewModel
    @ObservedObject var session: ArchiveBrowsingSession

    public init(sources: [URL], session: ArchiveBrowsingSession) {
        self.model = ArchiveCreationViewModel(sources: sources)
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Fixed Header
            HStack(spacing: 8) {
                // Capsule emblem
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.85, green: 0.25, blue: 0.45), Color(red: 0.05, green: 0.48, blue: 0.98)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 26)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 4, height: 16)
                }

                Text("创建压缩包")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // Scrollable Content Body
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Top Inputs Row: [名称] & [存储位置]
                    HStack(spacing: 16) {
                // Name Field
                VStack(alignment: .leading, spacing: 5) {
                    Text("名称")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    TextField("", text: $model.archiveStem)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity)

                // Destination Picker
                VStack(alignment: .leading, spacing: 5) {
                    Text("存储位置")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Button {
                        model.chooseDestinationFolder()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))

                            Text(model.destinationDirectory.lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }

            // Purpose Section: "这个压缩包将用于什么？"
            VStack(alignment: .leading, spacing: 8) {
                Text("这个压缩包将用于什么？")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 10) {
                    ForEach([
                        ArchiveCreationPurpose.general,
                        ArchiveCreationPurpose.windows,
                        ArchiveCreationPurpose.mac,
                        ArchiveCreationPurpose.linux,
                        ArchiveCreationPurpose.smallest
                    ]) { purpose in
                        PurposeTile(
                            purpose: purpose,
                            isSelected: model.selectedPurpose == purpose
                        ) {
                            model.applyPurposePreset(purpose)
                        }
                    }
                }
            }

            // Middle 2-Column Card: [压缩设置] | [压缩包概览]
            HStack(alignment: .top, spacing: 0) {
                // Left Column: 压缩设置
                VStack(alignment: .leading, spacing: 14) {
                    Text("压缩设置")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)

                    // Format Switcher
                    VStack(alignment: .leading, spacing: 6) {
                        Text("压缩格式")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            FormatPill(title: "ZIP", isSelected: model.selectedFormat == .zip) {
                                model.selectedFormat = .zip
                                model.syncFilenameExtension()
                            }
                            FormatPill(title: "7Z", isSelected: model.selectedFormat == .sevenZip) {
                                model.selectedFormat = .sevenZip
                                model.syncFilenameExtension()
                            }
                            FormatPill(title: "TAR", isSelected: model.selectedFormat == .tar) {
                                model.selectedFormat = .tar
                                model.syncFilenameExtension()
                            }
                        }
                        .padding(3)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Strength Slider with 5 Dots
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("压缩强度")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(model.strengthDisplayName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                        }

                        // Stepped Slider
                        Slider(
                            value: Binding(
                                get: { Double(model.sliderStep) },
                                set: { model.updateStrengthFromStep(Int($0)) }
                            ),
                            in: 0...4,
                            step: 1
                        )
                        .accentColor(Color(red: 0.05, green: 0.48, blue: 0.98))

                        HStack {
                            Text("更快")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            VStack(spacing: 1) {
                                Text(model.strengthDisplayName)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                                Text("兼顾速度和大小")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("更小")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Right Column: 压缩包概览
                VStack(alignment: .leading, spacing: 14) {
                    Text("压缩包概览")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 6) {
                        OverviewRow(label: "格式", value: model.selectedFormat == .sevenZip ? "7Z" : model.selectedFormat.rawValue.uppercased())
                        OverviewRow(label: "压缩强度", value: model.strengthDisplayName)
                        OverviewRow(label: "用途", value: model.selectedPurpose.title)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(purposeOverviewChecklist(for: model.selectedPurpose), id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))

                                Text(item)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )

            // Collapsible Row 1: 使用密码保护
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))

                    Text("使用密码保护")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Toggle("", isOn: $model.enableEncryption)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                if model.enableEncryption {
                    HStack(spacing: 10) {
                        if model.isShowingPasswordPlain {
                            TextField("输入解压密码", text: $model.password)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("输入解压密码", text: $model.password)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            model.isShowingPasswordPlain.toggle()
                        } label: {
                            Image(systemName: model.isShowingPasswordPlain ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if model.selectedFormat == .sevenZip {
                            Toggle("加密文件名", isOn: $model.encryptHeaders)
                                .toggleStyle(.checkbox)
                                .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(10)

            // Collapsible Row 2: 高级选项 (分卷压缩)
            VStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.isAdvancedExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("高级选项")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: model.isAdvancedExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if model.isAdvancedExpanded {
                    HStack(spacing: 12) {
                        Text("分卷大小:")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Picker("", selection: $model.selectedVolumeSize) {
                            Text(ArchiveCreationVolumeSize.none.displayName).tag(ArchiveCreationVolumeSize.none)
                            Text(ArchiveCreationVolumeSize.mb10.displayName).tag(ArchiveCreationVolumeSize.mb10)
                            Text(ArchiveCreationVolumeSize.mb100.displayName).tag(ArchiveCreationVolumeSize.mb100)
                            Text(ArchiveCreationVolumeSize.cd700.displayName).tag(ArchiveCreationVolumeSize.cd700)
                            Text(ArchiveCreationVolumeSize.dvd4700.displayName).tag(ArchiveCreationVolumeSize.dvd4700)
                        }
                        .frame(maxWidth: 200)

                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(10)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    Divider()

    // Fixed Footer Action Buttons
    HStack(spacing: 14) {
        Spacer()

        // Cancel Button (Red Pill)
        Button {
            session.creationSources = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                Text("取消")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(red: 0.85, green: 0.22, blue: 0.26))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)

        // Start Creation Button (Ocean Blue Gradient Pill)
        Button {
            if model.selectedPurpose == .windows {
                model.runCompatibilityCheck()
                if !model.compatibilityIssues.isEmpty {
                    model.isShowingCompatibilitySheet = true
                    return
                }
            }
            startCreation()
        } label: {
            HStack(spacing: 6) {
                // Capsule emblem
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 14, height: 16)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 3, height: 10)
                }

                Text("创建压缩包")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.05, green: 0.48, blue: 0.98)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(model.archiveStem.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 14)
    .background(Color(NSColor.windowBackgroundColor))
}
.frame(minWidth: 620, idealWidth: 660, maxWidth: 680, minHeight: 480, idealHeight: 560, maxHeight: 620)
.background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $model.isShowingCompatibilitySheet) {
            WindowsCompatibilityFixSheetView(
                model: model,
                onCancel: {
                    model.isShowingCompatibilitySheet = false
                },
                onConfirm: {
                    model.isShowingCompatibilitySheet = false
                    let remappings = model.buildPathRemappings()
                    startCreation(pathRemappings: remappings)
                }
            )
        }
    }

    private func purposeOverviewChecklist(for purpose: ArchiveCreationPurpose) -> [String] {
        switch purpose {
        case .windows:
            return [
                "规范文件编码 (强制 UTF-8 编码防乱码)",
                "检查 Windows 文件名兼容性",
                "给出文件名修改建议 (仅修改包内名称，不改动源文件)",
                "清理 macOS 辅助文件 (.DS_Store / ._* / .AppleDouble)"
            ]
        case .mac:
            return [
                "保留 macOS 辅助文件与元数据",
                "保留 Resource Fork 与扩展属性",
                "完美适配 Apple 归档实用工具"
            ]
        case .linux:
            return [
                "清理 macOS 辅助文件",
                "保留 POSIX 权限与属主",
                "适合 Unix 目录归档与服务器部署"
            ]
        case .smallest:
            return [
                "启用 7-Zip LZMA2 最大压缩算法",
                "清理冗余辅助文件与元数据",
                "优先减小压缩包体积"
            ]
        case .general, .custom:
            return [
                "全球通用标准 ZIP 规范",
                "默认清理 macOS 噪音辅助文件",
                "兼顾兼容性与解压速度"
            ]
        }
    }

    private func startCreation(pathRemappings: [String: String] = [:]) {
        let (rawStem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(model.archiveStem)
        let finalExt = model.selectedFormat == .sevenZip ? "7z" : model.selectedFormat.rawValue
        let finalURL = model.destinationDirectory.appendingPathComponent("\(rawStem).\(finalExt)")

        let profile = CompressionProfile(
            format: model.selectedFormat,
            level: model.compressionStrength.rawValue,
            volumeSize: model.selectedVolumeSize.byteCount,
            encryptHeaders: model.enableEncryption && model.encryptHeaders && model.selectedFormat == .sevenZip,
            password: model.enableEncryption && !model.password.isEmpty ? model.password : nil,
            preserveMacMetadata: model.selectedPurpose.preservesMacMetadata,
            pathRemappings: pathRemappings
        )

        let sources = model.sources
        let purposeTitle = model.selectedPurpose.title

        session.creationSources = nil

        Task {
            session.isBusy = true
            session.statusMessage = "正在按照「\(purposeTitle)」规范创建归档..."
            do {
                let registry = try ManagedTemporaryArtifactRegistry()
                let lease = try await registry.reserveArchivePublication(finalURL: finalURL)
                do {
                    try await session.broker.create(
                        sources: sources,
                        at: lease.stagedPrimaryURL,
                        profile: profile
                    ) { prog in
                        Task { @MainActor in
                            if let total = prog.total, total > 0 {
                                session.progressFraction = Double(prog.completed) / Double(total)
                            }
                        }
                    }
                    let res = try await lease.commit()
                    session.statusMessage = "归档创建成功: \(res.primaryURL.lastPathComponent)"
                    await session.openArchive(at: res.primaryURL)
                } catch {
                    await lease.rollbackAndWait()
                    throw error
                }
            } catch {
                session.statusMessage = "创建归档失败: \(error.localizedDescription)"
            }
            session.isBusy = false
            session.progressFraction = nil
        }
    }
}

// MARK: - Purpose Tile

private struct PurposeTile: View {
    let purpose: ArchiveCreationPurpose
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tileIconName(for: purpose))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(height: 24)

                VStack(spacing: 2) {
                    Text(purpose.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)

                    Text(purpose.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.35) : Color.clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func tileIconName(for purpose: ArchiveCreationPurpose) -> String {
        switch purpose {
        case .general:  return "person.2"
        case .windows:  return "square.grid.2x2.fill"
        case .mac:      return "display"
        case .linux:    return "terminal"
        case .smallest: return "leaf"
        case .custom:   return "slider.horizontal.3"
        }
    }
}

// MARK: - Format Pill

private struct FormatPill: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color(red: 0.05, green: 0.48, blue: 0.98) : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                        .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview Row

private struct OverviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
        }
    }
}
