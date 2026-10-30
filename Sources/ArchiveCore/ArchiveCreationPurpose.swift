import Foundation

/// Creation purpose presets for cross-platform archive optimization.
public enum ArchiveCreationPurpose: String, CaseIterable, Identifiable, Codable, Sendable {
    case general  = "general"
    case windows  = "windows"
    case mac      = "mac"
    case linux    = "linux"
    case smallest = "smallest"
    case custom   = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general:  return "通用分享"
        case .windows:  return "Windows 用户"
        case .mac:      return "Mac 之间传递"
        case .linux:    return "Linux 与服务器"
        case .smallest: return "尽可能小"
        case .custom:   return "自定义配置"
        }
    }

    public var subtitle: String {
        switch self {
        case .general:
            return "兼顾兼容性与效率"
        case .windows:
            return "优化跨平台使用"
        case .mac:
            return "保留 macOS 辅助文件"
        case .linux:
            return "适合 Unix 目录归档"
        case .smallest:
            return "优先减小压缩包体积"
        case .custom:
            return "自由配置压缩等级、加密密码与分卷大小"
        }
    }

    public var isPro: Bool {
        return false
    }

    public var systemImage: String {
        switch self {
        case .general:  return "person.2.fill"
        case .windows:  return "square.grid.2x2.fill"
        case .mac:      return "display"
        case .linux:    return "terminal.fill"
        case .smallest: return "leaf.fill"
        case .custom:   return "slider.horizontal.3"
        }
    }

    public var filtersMacAuxiliary: Bool {
        switch self {
        case .general, .windows, .linux, .smallest: return true
        case .mac, .custom: return false
        }
    }

    public var preservesMacMetadata: Bool {
        switch self {
        case .mac: return true
        case .general, .windows, .linux, .smallest: return false
        case .custom: return true
        }
    }

    public var defaultFormat: ArchiveFormat {
        switch self {
        case .general:  return .zip
        case .windows:  return .zip
        case .mac:      return .zip
        case .linux:    return .tar
        case .smallest: return .sevenZip
        case .custom:   return .sevenZip
        }
    }

    public var formatBadge: String {
        switch self {
        case .general:  return "ZIP · 跨平台通用"
        case .windows:  return "ZIP · Windows 优化"
        case .mac:      return "ZIP · 保留 Mac 属性"
        case .linux:    return "TAR · POSIX 标准"
        case .smallest: return "7Z · LZMA2 固实压缩"
        case .custom:   return "自由定制"
        }
    }

    public struct PurposeAdvantageItem: Identifiable, Sendable {
        public let id = UUID()
        public let icon: String
        public let title: String
        public let detail: String

        public init(icon: String, title: String, detail: String) {
            self.icon = icon
            self.title = title
            self.detail = detail
        }
    }

    public var advantagesList: [PurposeAdvantageItem] {
        switch self {
        case .general:
            return [
                PurposeAdvantageItem(
                    icon: "archivebox.fill",
                    title: "工作方式",
                    detail: "采用标准 ZIP 格式与 UTF-8 编码，自动剔除 .DS_Store、__MACOSX 等 Mac 专有隐藏元数据。"
                ),
                PurposeAdvantageItem(
                    icon: "globe",
                    title: "核心优势",
                    detail: "跨平台兼容性好，Windows、Mac、iOS、Android 均可原生直接双击解压，无需安装第三方解压软件。"
                ),
                PurposeAdvantageItem(
                    icon: "checkmark.circle.fill",
                    title: "适用场景",
                    detail: "日常办公协同、邮件附件、跨平台或多设备文件流转。"
                )
            ]

        case .windows:
            return [
                PurposeAdvantageItem(
                    icon: "square.grid.2x2.fill",
                    title: "工作方式",
                    detail: "采用 ZIP 格式，剥离 Mac 资源分叉（._*）与隐藏文件，自动校验并提示 Windows 不支持的特殊字符及保留名称。"
                ),
                PurposeAdvantageItem(
                    icon: "shield.lefthalf.filled",
                    title: "核心优势",
                    detail: "避免 Windows 资源管理器解压时出现乱码、多余影子文件或路径报错，确保在 PC 上顺畅打开。"
                ),
                PurposeAdvantageItem(
                    icon: "checkmark.circle.fill",
                    title: "适用场景",
                    detail: "向 Windows 客户或同事发送合同文书、开发资源与设计素材。"
                )
            ]

        case .mac:
            return [
                PurposeAdvantageItem(
                    icon: "display",
                    title: "工作方式",
                    detail: "采用 ZIP 格式，完整保留 APFS 扩展属性、Finder 标签、Unix 执行权限位与软链接。"
                ),
                PurposeAdvantageItem(
                    icon: "lock.shield.fill",
                    title: "核心优势",
                    detail: "还原 Mac 专属文件特性，应用程序包（.app）与脚本解压后权限完整，可直接运行而不会提示“文件已损坏”。"
                ),
                PurposeAdvantageItem(
                    icon: "checkmark.circle.fill",
                    title: "适用场景",
                    detail: "Mac 设备间传递 Xcode 工程、Final Cut 剪辑项目、已签名应用或开发配置文件。"
                )
            ]

        case .linux:
            return [
                PurposeAdvantageItem(
                    icon: "terminal.fill",
                    title: "工作方式",
                    detail: "采用 POSIX 标准 TAR / TAR.GZ 格式打包，记录标准权限掩码（如 755/644）、用户属组及符号链接。"
                ),
                PurposeAdvantageItem(
                    icon: "shippingbox.fill",
                    title: "核心优势",
                    detail: "与 Linux / Unix 命令行环境原生兼容，服务器端直接使用 tar 命令解包，保留脚本可执行权限。"
                ),
                PurposeAdvantageItem(
                    icon: "checkmark.circle.fill",
                    title: "适用场景",
                    detail: "服务器代码部署、Docker 容器数据归档与 Linux 生产环境备份。"
                )
            ]

        case .smallest:
            return [
                PurposeAdvantageItem(
                    icon: "arrow.down.forward.and.arrow.up.backward",
                    title: "工作方式",
                    detail: "采用 7-Zip (.7z) 格式与 LZMA2 固实压缩算法，将相似文件连续编码以消除跨文件冗余，并过滤 Mac 隐藏文件。"
                ),
                PurposeAdvantageItem(
                    icon: "chart.line.downtrend.xyaxis",
                    title: "核心优势",
                    detail: "同等内容下生成体积最小，对代码工程、文本日志、办公文档等数据压缩率突出，显著节省存储空间和传输流量。"
                ),
                PurposeAdvantageItem(
                    icon: "checkmark.circle.fill",
                    title: "适用场景",
                    detail: "长期归档冷备份、超大文件存储、或需严格控制附件体积（如邮件/网盘限制）时使用。"
                )
            ]

        case .custom:
            return [
                PurposeAdvantageItem(
                    icon: "slider.horizontal.3",
                    title: "工作方式",
                    detail: "自主选择 7Z、ZIP 或 TAR 格式与压缩等级（0~9），并可配置密码加密与分卷切片。"
                ),
                PurposeAdvantageItem(
                    icon: "key.fill",
                    title: "核心优势",
                    detail: "参数灵活度高，支持 7Z 格式下加密并隐藏文件名列表，支持按指定大小切分大文件以便分批传输。"
                ),
                PurposeAdvantageItem(
                    icon: "checkmark.circle.fill",
                    title: "适用场景",
                    detail: "私密数据加密归档、跨介质分卷存储或特殊参数定制。"
                )
            ]
        }
    }

    // MARK: - Windows Filename Compatibility Engine

    public struct WindowsCompatibilityIssue: Identifiable, Sendable, Hashable {
        public enum Reason: String, Sendable, Hashable {
            case illegalCharacter    = "包含 Windows 不支持的字符"
            case reservedDeviceName  = "使用了 Windows 保留的设备名称"
            case trailingDotOrSpace  = "名称末尾的点或空格在 Windows 中可能消失"
        }

        public let id: UUID
        public let originalPath: String
        public let reason: Reason
        public let invalidToken: String
        public let suggestedFilename: String
        public let suggestedPath: String

        public init(
            id: UUID = UUID(),
            originalPath: String,
            reason: Reason,
            invalidToken: String,
            suggestedFilename: String,
            suggestedPath: String
        ) {
            self.id = id
            self.originalPath = originalPath
            self.reason = reason
            self.invalidToken = invalidToken
            self.suggestedFilename = suggestedFilename
            self.suggestedPath = suggestedPath
        }

        public var reasonDescription: String {
            switch reason {
            case .reservedDeviceName:
                return "使用了 Windows 保留的设备名称"
            case .trailingDotOrSpace:
                if originalPath.hasSuffix(".") {
                    return "名称末尾的点在 Windows 中可能消失"
                } else {
                    return "名称末尾的空格在 Windows 中可能消失"
                }
            case .illegalCharacter:
                return "包含 Windows 不支持的字符: \(invalidToken)"
            }
        }
    }

    private static let windowsReservedNames: Set<String> = [
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    ]

    private static let windowsIllegalChars = CharacterSet(charactersIn: "\\/:*?\"<>|")

    /// Recursively enumerates relative paths inside the provided source URLs for deep compatibility checking.
    public static func enumerateRelativePaths(for sources: [URL]) -> [String] {
        var relativePaths: [String] = []
        let fm = FileManager.default

        for source in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { continue }
            let rootName = source.lastPathComponent

            if isDir.boolValue {
                relativePaths.append(rootName)
                if let enumerator = fm.enumerator(
                    at: source,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants]
                ) {
                    let basePrefix = source.path.hasSuffix("/") ? source.path : "\(source.path)/"
                    for case let fileURL as URL in enumerator {
                        let subPath = fileURL.path.replacingOccurrences(of: basePrefix, with: "")
                        guard !subPath.isEmpty else { continue }
                        relativePaths.append("\(rootName)/\(subPath)")
                    }
                }
            } else {
                relativePaths.append(rootName)
            }
        }
        return relativePaths
    }

    /// Inspects relative file paths for Windows NTFS/FAT32 illegal characters or reserved names.
    public static func validateWindowsCompatibility(paths: [String]) -> [WindowsCompatibilityIssue] {
        var issues: [WindowsCompatibilityIssue] = []

        for path in paths {
            let filename = (path as NSString).lastPathComponent
            guard !filename.isEmpty && filename != "." && filename != ".." else { continue }

            // 1. Trailing dot or space check
            if filename.hasSuffix(".") || filename.hasSuffix(" ") {
                let sanitizedFilename = filename.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                let parent = (path as NSString).deletingLastPathComponent
                let suggestedPath = parent.isEmpty ? sanitizedFilename : "\(parent)/\(sanitizedFilename)"
                issues.append(WindowsCompatibilityIssue(
                    originalPath: path,
                    reason: .trailingDotOrSpace,
                    invalidToken: String(filename.last ?? " "),
                    suggestedFilename: sanitizedFilename,
                    suggestedPath: suggestedPath
                ))
                continue
            }

            // 2. Illegal character check: \ / : * ? " < > | or control characters (0x00 - 0x1F)
            var foundIllegal: [Character] = []
            for ch in filename.unicodeScalars {
                if windowsIllegalChars.contains(ch) || ch.value < 32 {
                    foundIllegal.append(Character(ch))
                }
            }
            if !foundIllegal.isEmpty {
                var sanitizedFilename = filename
                for ch in foundIllegal {
                    sanitizedFilename = sanitizedFilename.replacingOccurrences(of: String(ch), with: "-")
                }
                let parent = (path as NSString).deletingLastPathComponent
                let suggestedPath = parent.isEmpty ? sanitizedFilename : "\(parent)/\(sanitizedFilename)"
                issues.append(WindowsCompatibilityIssue(
                    originalPath: path,
                    reason: .illegalCharacter,
                    invalidToken: foundIllegal.map(String.init).joined(separator: " "),
                    suggestedFilename: sanitizedFilename,
                    suggestedPath: suggestedPath
                ))
                continue
            }

            // 3. Reserved DOS device names (e.g. CON.txt -> CON-file.txt, PRN.docx -> PRN-file.docx)
            let stem = (filename as NSString).deletingPathExtension.uppercased()
            if windowsReservedNames.contains(stem) {
                let rawStem = (filename as NSString).deletingPathExtension
                let ext = (filename as NSString).pathExtension
                let sanitizedFilename = ext.isEmpty ? "\(rawStem)-file" : "\(rawStem)-file.\(ext)"
                let parent = (path as NSString).deletingLastPathComponent
                let suggestedPath = parent.isEmpty ? sanitizedFilename : "\(parent)/\(sanitizedFilename)"
                issues.append(WindowsCompatibilityIssue(
                    originalPath: path,
                    reason: .reservedDeviceName,
                    invalidToken: stem,
                    suggestedFilename: sanitizedFilename,
                    suggestedPath: suggestedPath
                ))
            }
        }

        return issues
    }
}

/// Split volume size presets for multi-volume archive creation.
public enum ArchiveCreationVolumeSize: Hashable, Identifiable, Sendable {
    case none
    case mb10
    case mb100
    case cd700
    case dvd4700
    case custom(bytes: Int64)

    public var id: String {
        switch self {
        case .none:           return "none"
        case .mb10:           return "10mb"
        case .mb100:          return "100mb"
        case .cd700:          return "700mb"
        case .dvd4700:        return "4700mb"
        case let .custom(b):  return "custom_\(b)"
        }
    }

    public var displayName: String {
        switch self {
        case .none:           return "不分卷 (单个归档)"
        case .mb10:           return "10 MB (邮件附件通用)"
        case .mb100:          return "100 MB (网盘常见分块)"
        case .cd700:          return "700 MB (标准 CD-R)"
        case .dvd4700:        return "4.7 GB (单层 DVD)"
        case let .custom(b):  return "自定义大小 (\(ByteCountFormatter.string(fromByteCount: b, countStyle: .file)))"
        }
    }

    public var byteCount: Int64? {
        switch self {
        case .none:           return nil
        case .mb10:           return 10 * 1024 * 1024
        case .mb100:          return 100 * 1024 * 1024
        case .cd700:          return 700 * 1024 * 1024
        case .dvd4700:        return Int64(4700) * 1024 * 1024
        case let .custom(b):  return b > 0 ? b : nil
        }
    }
}

/// Compression strength levels for archive creation.
public enum ArchiveCompressionStrength: Int, CaseIterable, Identifiable, Sendable {
    case store    = 0
    case fastest  = 1
    case standard = 6
    case maximum  = 9

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .store:    return "仅存储 (Store 0)"
        case .fastest:  return "快速压缩 (Fast 1)"
        case .standard: return "标准压缩 (Default 6)"
        case .maximum:  return "极限压缩 (Max 9)"
        }
    }
}
