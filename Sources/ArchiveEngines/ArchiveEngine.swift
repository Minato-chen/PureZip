import Foundation
import ArchiveCore

public enum ArchiveEngineError: Error, LocalizedError, Sendable {
    case unsupportedFormat(String)
    case unsupportedCapability(ArchiveFormat, ArchiveCapabilitySet)
    case invalidArchive(String)
    case unsafePath(String)
    case wrongPassword
    case engineFailure(backend: String, detail: String)
    case io(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(path):
            return "Unsupported archive format: \(path)"
        case let .unsupportedCapability(format, cap):
            return "Format \(format.rawValue) does not support required capabilities (\(cap.rawValue))"
        case let .invalidArchive(reason):
            return "Invalid or corrupted archive: \(reason)"
        case let .unsafePath(path):
            return "Unsafe archive entry path rejected: \(path)"
        case .wrongPassword:
            return "Password required or incorrect password"
        case let .engineFailure(backend, detail):
            return "Engine [\(backend)] failure: \(detail)"
        case let .io(msg):
            return "I/O error: \(msg)"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

extension ArchiveEngineError: Equatable {
    public static func == (lhs: ArchiveEngineError, rhs: ArchiveEngineError) -> Bool {
        switch (lhs, rhs) {
        case (.wrongPassword, .wrongPassword): return true
        case (.cancelled, .cancelled): return true
        case let (.unsupportedFormat(a), .unsupportedFormat(b)): return a == b
        case let (.unsupportedCapability(f1, c1), .unsupportedCapability(f2, c2)): return f1 == f2 && c1 == c2
        case let (.invalidArchive(a), .invalidArchive(b)): return a == b
        case let (.unsafePath(a), .unsafePath(b)): return a == b
        case let (.engineFailure(b1, d1), .engineFailure(b2, d2)): return b1 == b2 && d1 == d2
        case let (.io(a), .io(b)): return a == b
        default: return false
        }
    }
}

/// Unified protocol conformed to by `ZIPEngine`, `SevenZipEngine`, `BSDTarEngine`,
/// `CompressedStreamEngine`, `LzipEngine`, and `DiskImageEngine`.
public protocol ArchiveEngine: Sendable {
    var id: String { get }
    var supportedFormats: Set<ArchiveFormat> { get }

    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilitySet
    func probe(_ url: URL) async throws -> ArchiveFormatDescriptor?
    func list(_ url: URL, password: String?) -> AsyncThrowingStream<[ArchiveEntry], Error>
    func extract(
        _ url: URL,
        entries: [ArchiveEntry],
        to destination: URL,
        password: String?,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)?
    ) async throws
    func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile,
        sourceMode: ArchiveCreationSourceMode,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)?
    ) async throws
    func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)?
    ) async throws
    func test(_ url: URL, password: String?) async throws
}

extension ArchiveEngine {
    /// Validates that an extracted entry path cannot escape `destination` via `..` or absolute paths.
    public static func validatedDestinationURL(for entryPath: String, inside destination: URL) throws -> URL {
        let rawParts = entryPath.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        if rawParts.contains("..") {
            throw ArchiveEngineError.unsafePath(entryPath)
        }
        let cleanRel = rawParts.filter { !$0.isEmpty && $0 != "." }.joined(separator: "/")
        guard !cleanRel.isEmpty else {
            throw ArchiveEngineError.unsafePath(entryPath)
        }
        let target = destination.appendingPathComponent(cleanRel).standardizedFileURL
        let rootPath = destination.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard target.path == rootPath || target.path.hasPrefix(rootPrefix) else {
            throw ArchiveEngineError.unsafePath(entryPath)
        }
        return target
    }
}
