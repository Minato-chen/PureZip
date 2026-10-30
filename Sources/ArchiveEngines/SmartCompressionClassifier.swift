import Foundation
import zlib

/// Smart compression planner & classifier for archive creation (`extensionPrior`, `signature`,
/// `sampled`, `smallNeutralFile`, `directStoreFiles`, `directDeflateFiles`, `probeStoreFiles`,
/// `probeDeflateFiles`, `noInflationFallbackFiles`).
public enum SmartCompressionClassifier {

    public enum Intent: String, Codable, Sendable, Hashable {
        case store
        case compress
    }

    public enum EvidenceKind: String, Codable, Sendable, Hashable {
        case profileOverride
        case smallNeutralFile
        case extensionPrior
        case signature
        case sampled
    }

    public struct FileDecision: Codable, Sendable, Hashable {
        public let url: URL
        public let size: Int64
        public let intent: Intent
        public let evidence: EvidenceKind
        public let estimatedRatio: Double

        public init(url: URL, size: Int64, intent: Intent, evidence: EvidenceKind, estimatedRatio: Double) {
            self.url = url
            self.size = size
            self.intent = intent
            self.evidence = evidence
            self.estimatedRatio = estimatedRatio
        }
    }

    private static let precompressedExtensions: Set<String> = [
        "zip", "7z", "rar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "lz", "zst",
        "jpg", "jpeg", "png", "webp", "heic", "avif", "gif",
        "mp4", "m4v", "mov", "mkv", "webm", "mp3", "m4a", "aac", "flac", "ogg",
        "dmg", "pkg", "ipa", "apk", "jar", "woff2"
    ]

    private static let compressibleExtensions: Set<String> = [
        "txt", "md", "json", "xml", "yaml", "yml", "plist", "html", "css", "js", "ts",
        "swift", "c", "h", "cpp", "py", "rs", "go", "java", "kt", "rb", "sh", "sql",
        "csv", "tsv", "log", "svg", "bmp", "wav", "tar"
    ]

    public static let initialProbeChunkBytes = 16 * 1024
    public static let minimumCompressionSavingsRatio = 0.96

    public static func classify(fileAt url: URL, compressionLevel: Int = 6) -> FileDecision {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        // 1. Level 0 profile override -> always STORE
        if compressionLevel <= 0 {
            return FileDecision(url: url, size: size, intent: .store, evidence: .profileOverride, estimatedRatio: 1.0)
        }

        // 2. Tiny files (< 64 bytes) gain nothing from Deflate header overhead
        if size < 64 {
            return FileDecision(url: url, size: size, intent: .store, evidence: .smallNeutralFile, estimatedRatio: 1.0)
        }

        let ext = url.pathExtension.lowercased()
        // 3. Extension priors
        if precompressedExtensions.contains(ext) {
            return FileDecision(url: url, size: size, intent: .store, evidence: .extensionPrior, estimatedRatio: 1.0)
        }
        if compressibleExtensions.contains(ext) {
            return FileDecision(url: url, size: size, intent: .compress, evidence: .extensionPrior, estimatedRatio: 0.45)
        }

        // 4. Magic signature & sample chunk probe
        guard let handle = try? FileHandle(forReadingFrom: url),
              let sample = try? handle.read(upToCount: initialProbeChunkBytes),
              !sample.isEmpty else {
            return FileDecision(url: url, size: size, intent: .compress, evidence: .sampled, estimatedRatio: 0.8)
        }
        try? handle.close()

        let bytes = [UInt8](sample)
        // Check known compressed binary magic signatures (PNG, JPEG, ZIP, 7z, Gzip, Zstd)
        if isKnownCompressedMagic(bytes) {
            return FileDecision(url: url, size: size, intent: .store, evidence: .signature, estimatedRatio: 1.0)
        }

        // Sampled Deflate probe on first chunk
        if let compressedSample = rawDeflate(sample, level: 1) {
            let ratio = Double(compressedSample.count) / Double(sample.count)
            let intent: Intent = ratio < minimumCompressionSavingsRatio ? .compress : .store
            return FileDecision(url: url, size: size, intent: intent, evidence: .sampled, estimatedRatio: ratio)
        }

        return FileDecision(url: url, size: size, intent: .compress, evidence: .sampled, estimatedRatio: 0.85)
    }

    private static func isKnownCompressedMagic(_ b: [UInt8]) -> Bool {
        guard b.count >= 6 else { return false }
        // PNG: 89 50 4E 47
        if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return true }
        // JPEG: FF D8 FF
        if b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF { return true }
        // ZIP: 50 4B 03 04
        if b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04 { return true }
        // Gzip: 1F 8B
        if b[0] == 0x1F && b[1] == 0x8B { return true }
        // 7z: 37 7A BC AF 27 1C
        if b[0] == 0x37 && b[1] == 0x7A && b[2] == 0xBC && b[3] == 0xAF { return true }
        return false
    }

    /// Raw Deflate compression (windowBits = -15) used by both sampling probe and `NativeStreamingZIPWriter`.
    public static func rawDeflate(_ data: Data, level: Int32 = Z_DEFAULT_COMPRESSION) -> Data? {
        if data.isEmpty { return Data() }
        var stream = z_stream()
        let initRc = deflateInit2_(
            &stream,
            level,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initRc == Z_OK else { return nil }
        defer { deflateEnd(&stream) }

        let bound = Int(deflateBound(&stream, uLong(data.count))) + 64
        var out = Data(count: bound)

        let rc: Int32 = data.withUnsafeBytes { inBuf in
            out.withUnsafeMutableBytes { outBuf in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inBuf.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(bound)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }
        guard rc == Z_STREAM_END else { return nil }
        out.count = Int(stream.total_out)
        return out
    }

    /// Raw Inflate decompression (windowBits = -15) for ZIP method 8 entries.
    public static func rawInflate(_ data: Data, expectedUncompressedSize: Int) throws -> Data {
        if data.isEmpty { return Data() }
        var stream = z_stream()
        let initRc = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initRc == Z_OK else {
            throw ArchiveEngineError.invalidArchive("zlib inflateInit2 failed (\(initRc))")
        }
        defer { inflateEnd(&stream) }

        var capacity = max(expectedUncompressedSize, data.count * 2, 4096)
        var out = Data(count: capacity)

        return try data.withUnsafeBytes { inBuf in
            guard let inBase = inBuf.bindMemory(to: Bytef.self).baseAddress else {
                return Data()
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inBase)
            stream.avail_in = uInt(data.count)

            while true {
                let writtenSoFar = Int(stream.total_out)
                if writtenSoFar >= capacity {
                    // Prevent zip-bomb unbounded memory explosion: max 1GB uncompressed in memory
                    guard capacity <= 1024 * 1024 * 1024 else {
                        throw ArchiveEngineError.invalidArchive("Decompressed stream exceeds 1GB memory limit")
                    }
                    capacity = max(capacity * 2, capacity + 65536)
                    out.count = capacity
                }
                let status: Int32 = try out.withUnsafeMutableBytes { outBuf in
                    guard let base = outBuf.bindMemory(to: Bytef.self).baseAddress else {
                        throw ArchiveEngineError.invalidArchive("Failed to bind output buffer memory")
                    }
                    stream.next_out = base.advanced(by: writtenSoFar)
                    stream.avail_out = uInt(capacity - writtenSoFar)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                if status == Z_STREAM_END {
                    out.count = Int(stream.total_out)
                    return out
                }
                if status != Z_OK && status != Z_BUF_ERROR {
                    throw ArchiveEngineError.invalidArchive("Deflate stream corrupted (status \(status))")
                }
                if status == Z_BUF_ERROR && stream.avail_in == 0 && Int(stream.total_out) < capacity {
                    out.count = Int(stream.total_out)
                    return out
                }
            }
        }
    }

    public static func crc32Checksum(for data: Data) -> UInt32 {
        let initial = zlib.crc32(0, nil, 0)
        let computed = data.withUnsafeBytes { rawBuf -> uLong in
            guard let ptr = rawBuf.bindMemory(to: Bytef.self).baseAddress else {
                return initial
            }
            return zlib.crc32(initial, ptr, uInt(data.count))
        }
        return UInt32(computed & 0xFFFF_FFFF)
    }
}
