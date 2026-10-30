import AppKit
import FinderSync
import ArchiveCore
import PureZipFinderSupport

/// Finder Sync extension controller providing PureZip context menu actions in Finder.
@objc(FinderSync)
public final class FinderSync: FIFinderSync {
    private let requestStore = FinderActionRequestStore()

    public override init() {
        super.init()
        NSLog("PureZipFinderSync: FinderSync init() started")
        configureMonitoredVolumes()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMonitoringPreferencesChanged(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        NSLog("PureZipFinderSync: FinderSync init() finished successfully")
    }

    private func configureMonitoredVolumes() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: Set<URL> = [home, URL(fileURLWithPath: "/Users")]
        if let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            for vol in mounted {
                if vol.path != "/" && vol.path != "/System/Volumes/Data" {
                    urls.insert(vol)
                }
            }
        }
        FIFinderSyncController.default().directoryURLs = urls

        if let badgeImg = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: "PureZip") {
            FIFinderSyncController.default().setBadgeImage(badgeImg, label: "PureZip", forBadgeIdentifier: "PureZipBadge")
        }
        NSLog("PureZipFinderSync: Configured directoryURLs: %@", urls.map(\.path).joined(separator: ", "))
    }

    @objc public func handleMonitoringPreferencesChanged(_ notification: Notification) {
        configureMonitoredVolumes()
    }

    public override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        NSLog("PureZipFinderSync: menu(for: %ld) requested", menuKind.rawValue)
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targeted = FIFinderSyncController.default().targetedURL()
        let subMenu = NSMenu(title: "PureZip")

        if menuKind == .contextualMenuForItems || (!selected.isEmpty && menuKind != .contextualMenuForContainer) {
            let activeItems = !selected.isEmpty ? selected : (targeted.map { [$0] } ?? [])
            guard !activeItems.isEmpty else { return nil }

            // 1. Detect archives and deduplicate multi-volume split parts (e.g. .001, .002, .003 -> 1 archive)
            let archiveCandidates = activeItems.filter { ArchiveFormatDescriptor.detect(at: $0).format != .unknown }
            let dedupedArchives = ArchiveVolumeFamily.deduplicatedPrimaryArchives(from: archiveCandidates)
            let hasArchives = !dedupedArchives.isEmpty

            if hasArchives {
                if dedupedArchives.count == 1 {
                    let singleArchive = dedupedArchives[0]
                    let folderStem = ArchiveVolumeFamily.extractionFolderStem(for: singleArchive)

                    subMenu.addItem(makeItem(
                        title: "用 PureZip 浏览归档",
                        action: #selector(browseArchive(_:)),
                        symbol: "doc.text.magnifyingglass"
                    ))

                    subMenu.addItem(NSMenuItem.separator())

                    subMenu.addItem(makeItem(
                        title: "解压到 \"\(folderStem)/\"",
                        action: #selector(quickExtractToNamedFolder(_:)),
                        symbol: "folder.badge.plus"
                    ))

                    subMenu.addItem(makeItem(
                        title: "解压到当前文件夹",
                        action: #selector(quickExtractHere(_:)),
                        symbol: "arrow.down.doc"
                    ))

                    subMenu.addItem(makeItem(
                        title: "解压到...",
                        action: #selector(quickExtractTo(_:)),
                        symbol: "ellipsis.circle"
                    ))

                    subMenu.addItem(NSMenuItem.separator())

                    subMenu.addItem(makeItem(
                        title: "测试压缩包完整性",
                        action: #selector(testArchive(_:)),
                        symbol: "checkmark.shield"
                    ))
                } else {
                    subMenu.addItem(makeItem(
                        title: "分别解压到各个同名文件夹",
                        action: #selector(quickExtractBatchToNamedFolders(_:)),
                        symbol: "folder.badge.plus"
                    ))

                    subMenu.addItem(makeItem(
                        title: "全部解压到当前文件夹",
                        action: #selector(quickExtractBatchHere(_:)),
                        symbol: "arrow.down.doc"
                    ))

                    subMenu.addItem(makeItem(
                        title: "批量解压到...",
                        action: #selector(quickExtractBatchTo(_:)),
                        symbol: "ellipsis.circle"
                    ))

                    subMenu.addItem(NSMenuItem.separator())

                    subMenu.addItem(makeItem(
                        title: "批量测试压缩包",
                        action: #selector(testArchive(_:)),
                        symbol: "checkmark.shield"
                    ))
                }
            }

            // 2. Compression items
            if let firstURL = activeItems.first {
                if hasArchives {
                    subMenu.addItem(NSMenuItem.separator())
                }

                let (compStem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(firstURL.lastPathComponent)
                let targetStem = compStem.isEmpty ? "Archive" : compStem

                subMenu.addItem(makeItem(
                    title: "压缩为 \"\(targetStem).zip\"",
                    action: #selector(quickZIP(_:)),
                    symbol: "archivebox"
                ))

                subMenu.addItem(makeItem(
                    title: "压缩为 \"\(targetStem).7z\"",
                    action: #selector(quick7Z(_:)),
                    symbol: "archivebox.fill"
                ))

                subMenu.addItem(makeItem(
                    title: "添加到压缩包...",
                    action: #selector(advancedCompression(_:)),
                    symbol: "slider.horizontal.3"
                ))
            }
        } else if menuKind == .contextualMenuForContainer || menuKind == .toolbarItemMenu {
            if targeted != nil {
                subMenu.addItem(makeItem(
                    title: "新建压缩包...",
                    action: #selector(advancedCompressionForContainer(_:)),
                    symbol: "archivebox"
                ))
            }
            subMenu.addItem(makeItem(
                title: "打开 PureZip",
                action: #selector(openMainApp(_:)),
                symbol: "arrow.up.forward.app"
            ))
        } else {
            return nil
        }

        guard !subMenu.items.isEmpty else { return nil }

        let rootMenu = NSMenu(title: "")
        let rootItem = NSMenuItem(title: "PureZip", action: nil, keyEquivalent: "")
        if let icon = NSWorkspace.shared.icon(forFile: "/Applications/PureZip.app") as NSImage?,
           let smallIcon = icon.copy() as? NSImage {
            smallIcon.size = NSSize(width: 16, height: 16)
            rootItem.image = smallIcon
        } else if let sysImg = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: nil) {
            rootItem.image = sysImg
        }
        rootItem.submenu = subMenu
        rootMenu.addItem(rootItem)
        NSLog("PureZipFinderSync: menu(for:) returning rootMenu with %ld items in submenu", subMenu.items.count)
        return rootMenu
    }

    private func makeItem(
        title: String,
        action: Selector,
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol = symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    @objc public func browseArchive(_ sender: AnyObject?) {
        dispatchFinderAction(.browseArchive)
    }

    @objc public func quickExtractToNamedFolder(_ sender: AnyObject?) {
        dispatchFinderAction(.quickExtractToNamedFolder)
    }

    @objc public func quickExtractHere(_ sender: AnyObject?) {
        dispatchFinderAction(.quickExtractHere)
    }

    @objc public func quickExtractTo(_ sender: AnyObject?) {
        dispatchFinderAction(.quickExtractTo)
    }

    @objc public func quickExtractBatchToNamedFolders(_ sender: AnyObject?) {
        dispatchFinderAction(.quickExtractBatchToNamedFolders)
    }

    @objc public func quickExtractBatchHere(_ sender: AnyObject?) {
        dispatchFinderAction(.quickExtractBatchHere)
    }

    @objc public func quickExtractBatchTo(_ sender: AnyObject?) {
        dispatchFinderAction(.quickExtractBatchTo)
    }

    @objc public func testArchive(_ sender: AnyObject?) {
        dispatchFinderAction(.testArchive)
    }

    @objc public func quickZIP(_ sender: AnyObject?) {
        dispatchFinderAction(.quickZIP)
    }

    @objc public func quick7Z(_ sender: AnyObject?) {
        dispatchFinderAction(.quick7Z)
    }

    @objc public func advancedCompression(_ sender: AnyObject?) {
        dispatchFinderAction(.advancedCompression)
    }

    @objc public func advancedCompressionForContainer(_ sender: AnyObject?) {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        dispatchFinderAction(.advancedCompression, sources: [target])
    }

    @objc public func openMainApp(_ sender: AnyObject?) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.minato.purezip") ?? URL(string: "file:///Applications/PureZip.app") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func dispatchFinderAction(_ action: FinderActionRequest.Action, sources: [URL]? = nil) {
        let targets = sources ?? FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !targets.isEmpty else { return }
        do {
            let req = try FinderActionRequest(action: action, sources: targets)
            let fileURL = try requestStore.write(req)
            let launchURL = FinderActionLaunchURL.make(requestID: req.id, requestFileURL: fileURL)
            NSWorkspace.shared.open(launchURL)
        } catch {
            NSLog("PureZipFinderSync failed to dispatch action: %@", error.localizedDescription)
        }
    }
}

@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

@main
struct PureZipFinderSyncMain {
    static func main() {
        NSLog("PureZipFinderSync: process started! FinderSync class: %@", String(describing: NSClassFromString("FinderSync")))
        if CommandLine.arguments.contains("--self-check") {
            print("PureZipFinderSync extension binary ready (principal class: FinderSync)")
            return
        }
        _ = NSExtensionMain()
    }
}
