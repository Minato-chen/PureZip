import Foundation

// MARK: - ArchiveVolumeFamily

/// Multi-volume split archive detection and resolution.
/// Supports:
/// - Numeric split volumes: `archive.7z.001`, `archive.zip.001`, `archive.tar.001` (`001`...`999`)
/// - Spanned ZIP volumes: `archive.z01`, `archive.z02`, ..., `archive.zip`
/// - RAR split volumes: `archive.part1.rar`, `archive.part01.rar`, or legacy `archive.rar` + `archive.r00`...`archive.r99`
public enum ArchiveVolumeFamily {

    public static func isSplitArchive(at url: URL, fileManager: FileManager = .default) -> Bool {
        let name = url.lastPathComponent
        let lower = name.lowercased()

        // 1. Numeric `.001` ... `.999`
        if let dotIdx = lower.lastIndex(of: ".") {
            let ext = String(lower[lower.index(after: dotIdx)...])
            if ext.count == 3, let num = Int(ext), (1...999).contains(num) {
                return true
            }
            // Spanned ZIP `.z01` ... `.z99`
            if ext.count == 3, ext.hasPrefix("z"), let num = Int(ext.dropFirst()), (1...99).contains(num) {
                return true
            }
            // Legacy RAR `.r00` ... `.r99`
            if ext.count == 3, ext.hasPrefix("r"), let num = Int(ext.dropFirst()), (0...99).contains(num) {
                return true
            }
        }

        // 2. `.partN.rar`
        if lower.range(of: #"\.part\d+\.rar$"#, options: .regularExpression) != nil {
            return true
        }

        // 3. `.zip` accompanied by `.z01` in the same directory
        if lower.hasSuffix(".zip") {
            let z01URL = url.deletingPathExtension().appendingPathExtension("z01")
            if fileManager.fileExists(atPath: z01URL.path) {
                return true
            }
        }

        // 4. `.rar` accompanied by `.r00` in the same directory
        if lower.hasSuffix(".rar") {
            let r00URL = url.deletingPathExtension().appendingPathExtension("r00")
            if fileManager.fileExists(atPath: r00URL.path) {
                return true
            }
        }

        return false
    }

    public static func primaryURL(for url: URL, fileManager: FileManager = .default) -> URL {
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let lower = name.lowercased()

        // 1. Numeric `.001` ... `.999` -> primary is `.001`
        if let dotIdx = name.lastIndex(of: ".") {
            let ext = String(name[name.index(after: dotIdx)...]).lowercased()
            if ext.count == 3, let num = Int(ext), (1...999).contains(num) {
                let stem = String(name[..<dotIdx])
                let candidate = dir.appendingPathComponent("\(stem).001")
                return candidate
            }
            // Spanned ZIP `.z01` ... `.z99` -> primary is `.zip` if present, else `.z01`
            if ext.count == 3, ext.hasPrefix("z"), let num = Int(ext.dropFirst()), (1...99).contains(num) {
                let stem = String(name[..<dotIdx])
                let zipCandidate = dir.appendingPathComponent("\(stem).zip")
                if fileManager.fileExists(atPath: zipCandidate.path) {
                    return zipCandidate
                }
                return dir.appendingPathComponent("\(stem).z01")
            }
            // Legacy RAR `.r00` ... `.r99` -> primary is `.rar` if present
            if ext.count == 3, ext.hasPrefix("r"), let num = Int(ext.dropFirst()), (0...99).contains(num) {
                let stem = String(name[..<dotIdx])
                let rarCandidate = dir.appendingPathComponent("\(stem).rar")
                if fileManager.fileExists(atPath: rarCandidate.path) {
                    return rarCandidate
                }
                return dir.appendingPathComponent("\(stem).r00")
            }
        }

        // 2. `.partN.rar` -> `.part1.rar` or `.part01.rar`
        if let range = lower.range(of: #"\.part(\d+)\.rar$"#, options: .regularExpression) {
            let prefix = String(name[..<range.lowerBound])
            let matchStr = String(lower[range])
            let digits = matchStr
                .replacingOccurrences(of: ".part", with: "")
                .replacingOccurrences(of: ".rar", with: "")
            let paddedOne = String(repeating: "0", count: max(0, digits.count - 1)) + "1"
            let candidate = dir.appendingPathComponent("\(prefix).part\(paddedOne).rar")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            return dir.appendingPathComponent("\(prefix).part1.rar")
        }

        return url
    }

    public static func ownershipURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let lower = name.lowercased()

        if let dotIdx = name.lastIndex(of: ".") {
            let ext = String(name[name.index(after: dotIdx)...]).lowercased()
            if ext.count == 3, let num = Int(ext), (1...999).contains(num) {
                let stem = String(name[..<dotIdx])
                return dir.appendingPathComponent(stem)
            }
            if ext.count == 3, (ext.hasPrefix("z") || ext.hasPrefix("r")), Int(ext.dropFirst()) != nil {
                let stem = String(name[..<dotIdx])
                return dir.appendingPathComponent(stem)
            }
        }
        if let range = lower.range(of: #"\.part\d+\.rar$"#, options: .regularExpression) {
            let prefix = String(name[..<range.lowerBound])
            return dir.appendingPathComponent("\(prefix).rar")
        }
        return url
    }

    /// Derives the clean subfolder name when extracting an archive into a dedicated folder.
    /// Strips multi-volume split suffixes (`.001`, `.part1.rar`, `.z01`) and compound extensions (`.tar.gz`).
    public static func extractionFolderStem(for url: URL) -> String {
        let owner = ownershipURL(for: url)
        let (stem, _) = ArchiveOutputFamily.splitArchiveStemAndCompoundExtension(owner.lastPathComponent)
        if !stem.isEmpty {
            return stem
        }
        let fallback = url.deletingPathExtension().lastPathComponent
        return fallback.isEmpty ? "Archive" : fallback
    }

    /// Deduplicates URLs that belong to the same split volume family.
    /// E.g. selecting `backup.7z.001`, `backup.7z.002`, `backup.7z.003` yields a single primary `backup.7z.001`.
    public static func deduplicatedPrimaryArchives(from urls: [URL], fileManager: FileManager = .default) -> [URL] {
        var seen = Set<URL>()
        var result: [URL] = []
        for raw in urls {
            let primary = primaryURL(for: raw, fileManager: fileManager)
            if !seen.contains(primary) {
                seen.insert(primary)
                result.append(primary)
            }
        }
        return result
    }

    public static func memberURLs(for url: URL, fileManager: FileManager = .default) -> [URL] {
        let primary = primaryURL(for: url, fileManager: fileManager)
        let dir = primary.deletingLastPathComponent()
        let name = primary.lastPathComponent
        let lower = name.lowercased()

        // Numeric `.001` sequence
        if lower.hasSuffix(".001") {
            let stem = String(name.dropLast(4))
            var members: [URL] = []
            for idx in 1...999 {
                let member = dir.appendingPathComponent(String(format: "%@.%03d", stem, idx))
                if fileManager.fileExists(atPath: member.path) {
                    members.append(member)
                } else {
                    break
                }
            }
            return members.isEmpty ? [primary] : members
        }

        // Spanned ZIP `.z01` ... `.zip`
        if lower.hasSuffix(".zip") {
            let stem = String(name.dropLast(4))
            var members: [URL] = []
            for idx in 1...99 {
                let zMember = dir.appendingPathComponent(String(format: "%@.z%02d", stem, idx))
                if fileManager.fileExists(atPath: zMember.path) {
                    members.append(zMember)
                } else {
                    break
                }
            }
            members.append(primary)
            return members
        }

        // `.part1.rar` / `.part01.rar`
        if let range = lower.range(of: #"\.part(\d+)\.rar$"#, options: .regularExpression) {
            let prefix = String(name[..<range.lowerBound])
            let matchStr = String(lower[range])
            let digits = matchStr
                .replacingOccurrences(of: ".part", with: "")
                .replacingOccurrences(of: ".rar", with: "")
            let width = digits.count
            var members: [URL] = []
            for idx in 1...999 {
                let numStr = String(format: "%0*d", width, idx)
                let member = dir.appendingPathComponent("\(prefix).part\(numStr).rar")
                if fileManager.fileExists(atPath: member.path) {
                    members.append(member)
                } else {
                    break
                }
            }
            return members.isEmpty ? [primary] : members
        }

        return [primary]
    }
}

// MARK: - ArchiveOutputFamily

/// Output naming, split-member URL generation, and collision-free base URL resolution.
public enum ArchiveOutputFamily {

    public static func sequentialMemberURL(baseURL: URL, index: Int) -> URL {
        let dir = baseURL.deletingLastPathComponent()
        let name = baseURL.lastPathComponent
        return dir.appendingPathComponent(String(format: "%@.%03d", name, max(1, index)))
    }

    public static func destinationMemberURLs(at baseURL: URL, splitMemberCount: Int?) -> [URL] {
        guard let count = splitMemberCount, count > 0 else {
            return [baseURL]
        }
        return (1...count).map { sequentialMemberURL(baseURL: baseURL, index: $0) }
    }

    public static func existingMemberURLs(at baseURL: URL, fileManager: FileManager = .default) -> [URL] {
        var urls: [URL] = []
        if fileManager.fileExists(atPath: baseURL.path) {
            urls.append(baseURL)
        }
        for idx in 1...999 {
            let member = sequentialMemberURL(baseURL: baseURL, index: idx)
            if fileManager.fileExists(atPath: member.path) {
                urls.append(member)
            } else if idx > 1 {
                break
            }
        }
        return urls
    }

    public static func outputExists(at baseURL: URL, fileManager: FileManager = .default) -> Bool {
        !existingMemberURLs(at: baseURL, fileManager: fileManager).isEmpty
    }

    public static func collisionFreeBaseURL(for proposedURL: URL, fileManager: FileManager = .default) -> URL {
        if !outputExists(at: proposedURL, fileManager: fileManager) {
            return proposedURL
        }
        let dir = proposedURL.deletingLastPathComponent()
        let filename = proposedURL.lastPathComponent
        let (stem, extWithDot) = splitArchiveStemAndCompoundExtension(filename)

        for counter in 2...10_000 {
            let candidate = dir.appendingPathComponent("\(stem) \(counter)\(extWithDot)")
            if !outputExists(at: candidate, fileManager: fileManager) {
                return candidate
            }
        }
        return dir.appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(8))\(extWithDot)")
    }

    public static func splitArchiveStemAndCompoundExtension(_ filename: String) -> (stem: String, extWithDot: String) {
        let lower = filename.lowercased()
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.lz", ".tar.zst"] {
            if lower.hasSuffix(compound) {
                let stemEnd = filename.index(filename.endIndex, offsetBy: -compound.count)
                return (String(filename[..<stemEnd]), String(filename[stemEnd...]))
            }
        }
        if let dot = filename.lastIndex(of: "."), dot != filename.startIndex {
            return (String(filename[..<dot]), String(filename[dot...]))
        }
        return (filename, "")
    }
}
