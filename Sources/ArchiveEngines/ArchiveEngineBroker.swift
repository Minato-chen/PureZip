import Foundation
import ArchiveCore

/// Multi-engine router and coordinator for archive probing, listing, extraction, and creation.
public actor ArchiveEngineBroker {
    public let engines: [any ArchiveEngine]
    public let workerTransport: (any ArchiveWorkerTransport)?
    private var confirmedProbeDescriptors: [URL: (fingerprint: ArchiveSourceFingerprint, descriptor: ArchiveFormatDescriptor)] = [:]

    public init(
        engines: [any ArchiveEngine]? = nil,
        workerTransport: (any ArchiveWorkerTransport)? = nil
    ) {
        self.engines = engines ?? [
            ZIPEngine(),
            BSDTarEngine(),
            CompressedStreamEngine(),
            LzipEngine(),
            DiskImageEngine(),
            SevenZipEngine()
        ]
        self.workerTransport = workerTransport
    }

    public func descriptor(for url: URL) async throws -> ArchiveFormatDescriptor {
        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        if let fp = try? ArchiveSourceFingerprint.capture(at: primary),
           let cached = confirmedProbeDescriptors[primary],
           cached.fingerprint == fp {
            return cached.descriptor
        }

        for eng in engines {
            if let probed = try await eng.probe(primary), probed.format != .unknown {
                if let fp = try? ArchiveSourceFingerprint.capture(at: primary) {
                    confirmedProbeDescriptors[primary] = (fp, probed)
                }
                return probed
            }
        }

        let fallback = ArchiveFormatDescriptor.detect(at: primary)
        if fallback.format == .unknown {
            throw ArchiveEngineError.unsupportedFormat(primary.path)
        }
        return fallback
    }

    public func engine(
        for url: URL,
        requiring capabilities: ArchiveCapabilitySet = [.list]
    ) async throws -> any ArchiveEngine {
        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        let desc = try await descriptor(for: primary)
        let isSplit = ArchiveVolumeFamily.isSplitArchive(at: url)
        let required = isSplit ? capabilities.union([.splitVolumes]) : capabilities

        // Prefer native ZIPEngine for single-volume standard ZIP archives
        if desc.format == .zip && !isSplit && !required.contains(.encrypt) {
            if let zipEng = engines.first(where: { $0.id == "zip" }),
               zipEng.capabilities(for: .zip).isSuperset(of: required) {
                return zipEng
            }
        }

        // Prefer BSDTarEngine for TAR archives
        if desc.format == .tar && !isSplit {
            if let tarEng = engines.first(where: { $0.id == "bsdtar" }),
               tarEng.capabilities(for: .tar).isSuperset(of: required) {
                return tarEng
            }
        }

        for eng in engines where eng.supportedFormats.contains(desc.format) {
            if eng.id == "sevenZip", let sz = eng as? SevenZipEngine, !sz.isAvailable {
                continue
            }
            if eng.capabilities(for: desc.format).isSuperset(of: required) {
                return eng
            }
        }

        throw ArchiveEngineError.unsupportedCapability(desc.format, required)
    }

    public func initialRootEntries(
        _ url: URL,
        format: ArchiveFormat? = nil,
        limit: Int = 200
    ) async throws -> [ArchiveEntry] {
        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        let fmt: ArchiveFormat
        if let format {
            fmt = format
        } else {
            fmt = try await descriptor(for: primary).format
        }
        if fmt == .zip && !ArchiveVolumeFamily.isSplitArchive(at: url) {
            return try await ZIPEngine().rootEntries(primary, limit: limit)
        }

        let eng = try await engine(for: primary, requiring: [.list])
        var all: [ArchiveEntry] = []
        for try await batch in eng.list(primary, password: nil) {
            all.append(contentsOf: batch)
        }
        let roots = ArchiveBrowserProjection.directChildren(of: all, in: "", includeAuxiliary: false)
        return Array(roots.prefix(limit))
    }

    public func list(
        _ url: URL,
        password: String? = nil,
        catalogID: UUID? = nil,
        commentHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> AsyncThrowingStream<[ArchiveEntry], Error> {
        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        let desc = try await descriptor(for: primary)
        if desc.format == .zip, !ArchiveVolumeFamily.isSplitArchive(at: url), let commentHandler {
            if let comment = try? await ZIPEngine().archiveComment(primary) {
                commentHandler(comment)
            }
        }
        let eng = try await engine(for: primary, requiring: [.list])
        return eng.list(primary, password: password)
    }

    public func extract(
        _ url: URL,
        entries: [ArchiveEntry],
        to destination: URL,
        password: String? = nil,
        catalogID: UUID? = nil,
        validatesDestination: Bool = true,
        selectionRoots: Bool = false,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        let eng = try await engine(for: primary, requiring: [.extract])
        try await eng.extract(primary, entries: entries, to: destination, password: password, progress: progress)
    }

    public func quickExtractAll(
        _ url: URL,
        to destination: URL,
        password: String? = nil,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        try await extract(url, entries: [], to: destination, password: password, progress: progress)
    }

    public func create(
        sources: [URL],
        at destination: URL,
        profile: CompressionProfile = CompressionProfile(format: .zip),
        sourceMode: ArchiveCreationSourceMode = .preparedDirect,
        executionPolicy: CompressionExecutionPolicy = .allAvailable,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        var required: ArchiveCapabilitySet = [.create]
        if profile.password != nil && !(profile.password?.isEmpty ?? true) {
            required.insert(.encrypt)
        }
        if profile.volumeSize != nil {
            required.insert(.splitVolumes)
        }

        // Select engine based on profile.format
        for eng in engines where eng.supportedFormats.contains(profile.format) {
            if eng.id == "sevenZip", let sz = eng as? SevenZipEngine, !sz.isAvailable {
                continue
            }
            if eng.capabilities(for: profile.format).isSuperset(of: required) {
                try await eng.create(
                    sources: sources,
                    at: destination,
                    profile: profile,
                    sourceMode: sourceMode,
                    progress: progress
                )
                return
            }
        }
        throw ArchiveEngineError.unsupportedCapability(profile.format, required)
    }

    public func apply(
        _ changes: ChangeSet,
        to archiveURL: URL,
        profile: CompressionProfile,
        executionPolicy: CompressionExecutionPolicy = .allAvailable,
        progress: (@Sendable (ArchiveTaskProgress) -> Void)? = nil
    ) async throws {
        let eng = try await engine(for: archiveURL, requiring: [.update])
        try await eng.apply(changes, to: archiveURL, profile: profile, progress: progress)
    }

    public func test(_ url: URL, password: String? = nil) async throws {
        let primary = ArchiveVolumeFamily.primaryURL(for: url)
        let eng = try await engine(for: primary, requiring: [.test])
        try await eng.test(primary, password: password)
    }
}

// MARK: - ArchiveWorkerRequestExecutor

/// Request executor actor inside `PureZipArchiveService.xpc`.
public actor ArchiveWorkerRequestExecutor {
    private struct CatalogSession {
        let id: UUID
        let sourceURL: URL
        let entries: [ArchiveEntry]
        let createdAt: Date
    }

    public let broker: ArchiveEngineBroker
    private var catalogSessions: [UUID: CatalogSession] = [:]
    private var catalogOrder: [UUID] = []
    private let maximumCatalogSessions = 8
    private let catalogLifetime: TimeInterval = 300

    public init(broker: ArchiveEngineBroker = ArchiveEngineBroker()) {
        self.broker = broker
    }

    public func execute(
        _ request: WorkerRequest,
        emit: @escaping @Sendable (WorkerResponse) -> Void
    ) async {
        do {
            switch request.operation {
            case .probe:
                guard let url = request.archiveURL else {
                    throw ArchiveEngineError.io("Missing archiveURL for probe")
                }
                let desc = try await broker.descriptor(for: url)
                emit(WorkerResponse(requestID: request.requestID, kind: .descriptor, descriptor: desc))
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .initialRootEntries:
                guard let url = request.archiveURL else {
                    throw ArchiveEngineError.io("Missing archiveURL for initialRootEntries")
                }
                let roots = try await broker.initialRootEntries(url, limit: request.rootLimit ?? 200)
                emit(WorkerResponse(requestID: request.requestID, kind: .indexBatch, entries: roots))
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .list:
                guard let url = request.archiveURL else {
                    throw ArchiveEngineError.io("Missing archiveURL for list")
                }
                var allEntries: [ArchiveEntry] = []
                let stream = try await broker.list(
                    url,
                    password: request.password,
                    catalogID: request.catalogID
                ) { comment in
                    emit(WorkerResponse(requestID: request.requestID, kind: .archiveComment, archiveComment: comment))
                }
                for try await batch in stream {
                    allEntries.append(contentsOf: batch)
                    emit(WorkerResponse(requestID: request.requestID, kind: .indexBatch, entries: batch))
                }
                if let catID = request.catalogID {
                    storeCatalogSession(id: catID, sourceURL: url, entries: allEntries)
                }
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .extract, .extractAll, .quickExtractAll:
                guard let url = request.archiveURL, let dest = request.destinationURL else {
                    throw ArchiveEngineError.io("Missing archiveURL or destinationURL for extract")
                }
                try await broker.extract(
                    url,
                    entries: request.entries ?? [],
                    to: dest,
                    password: request.password,
                    catalogID: request.catalogID
                ) { prog in
                    emit(WorkerResponse(requestID: request.requestID, kind: .progress, progress: prog))
                }
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .create:
                guard let sources = request.sources, let dest = request.destinationURL else {
                    throw ArchiveEngineError.io("Missing sources or destinationURL for create")
                }
                try await broker.create(
                    sources: sources,
                    at: dest,
                    profile: request.profile ?? CompressionProfile(format: .zip)
                ) { prog in
                    emit(WorkerResponse(requestID: request.requestID, kind: .progress, progress: prog))
                }
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .apply:
                guard let changes = request.changes, let url = request.archiveURL else {
                    throw ArchiveEngineError.io("Missing changes or archiveURL for apply")
                }
                try await broker.apply(
                    changes,
                    to: url,
                    profile: request.profile ?? CompressionProfile(format: .zip)
                ) { prog in
                    emit(WorkerResponse(requestID: request.requestID, kind: .progress, progress: prog))
                }
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .test:
                guard let url = request.archiveURL else {
                    throw ArchiveEngineError.io("Missing archiveURL for test")
                }
                try await broker.test(url, password: request.password)
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .releaseCatalog:
                if let catID = request.catalogID {
                    catalogSessions.removeValue(forKey: catID)
                    catalogOrder.removeAll { $0 == catID }
                }
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))

            case .shutdown, .acquireReadSession, .releaseReadSession, .directoryEntries:
                emit(WorkerResponse(requestID: request.requestID, kind: .completed))
            }
        } catch {
            emit(WorkerResponse(
                requestID: request.requestID,
                kind: .failed,
                errorMessage: error.localizedDescription
            ))
        }
    }

    public func shutdown() async {
        catalogSessions.removeAll()
        catalogOrder.removeAll()
    }

    private func storeCatalogSession(id: UUID, sourceURL: URL, entries: [ArchiveEntry]) {
        catalogSessions[id] = CatalogSession(id: id, sourceURL: sourceURL, entries: entries, createdAt: Date())
        catalogOrder.removeAll { $0 == id }
        catalogOrder.append(id)
        while catalogOrder.count > maximumCatalogSessions {
            let oldest = catalogOrder.removeFirst()
            catalogSessions.removeValue(forKey: oldest)
        }
    }
}
