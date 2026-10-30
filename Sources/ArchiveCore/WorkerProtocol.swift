import Foundation

// MARK: - XPC Objective-C Protocols

/// XPC worker protocol exposed by `PureZipArchiveService`.
@objc(PureZipWorkerXPCProtocol)
public protocol PureZipWorkerXPCProtocol {
    func submit(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func cancel(_ requestID: NSUUID)
    func invalidate(withReply reply: @escaping () -> Void)
}

/// XPC event sink protocol for streaming worker events from `PureZipArchiveService`.
@objc(PureZipWorkerXPCEventSinkProtocol)
public protocol PureZipWorkerXPCEventSinkProtocol {
    func receive(_ eventData: Data)
}

// MARK: - WorkerRequest & WorkerResponse

/// Operations supported by `ArchiveWorkerRequestExecutor.execute(_:emit:)`.
public struct WorkerRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case probe
        case list
        case initialRootEntries
        case acquireReadSession
        case releaseReadSession
        case directoryEntries
        case extract
        case extractAll
        case quickExtractAll
        case releaseCatalog
        case create
        case apply
        case test
        case shutdown
    }

    public let requestID: UUID
    public let operation: Operation
    public let archiveURL: URL?
    public let sources: [URL]?
    public let destinationURL: URL?
    public let entries: [ArchiveEntry]?
    public let directoryPath: String?
    public let password: String?
    public let catalogID: UUID?
    public let rootLimit: Int?
    public let profile: CompressionProfile?
    public let changes: ChangeSet?

    public init(
        requestID: UUID = UUID(),
        operation: Operation,
        archiveURL: URL? = nil,
        sources: [URL]? = nil,
        destinationURL: URL? = nil,
        entries: [ArchiveEntry]? = nil,
        directoryPath: String? = nil,
        password: String? = nil,
        catalogID: UUID? = nil,
        rootLimit: Int? = nil,
        profile: CompressionProfile? = nil,
        changes: ChangeSet? = nil
    ) {
        self.requestID = requestID
        self.operation = operation
        self.archiveURL = archiveURL
        self.sources = sources
        self.destinationURL = destinationURL
        self.entries = entries
        self.directoryPath = directoryPath
        self.password = password
        self.catalogID = catalogID
        self.rootLimit = rootLimit
        self.profile = profile
        self.changes = changes
    }
}

public struct WorkerResponse: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case descriptor
        case indexBatch
        case archiveComment
        case progress
        case completed
        case failed
    }

    public let requestID: UUID
    public let kind: Kind
    public let descriptor: ArchiveFormatDescriptor?
    public let entries: [ArchiveEntry]?
    public let archiveComment: String?
    public let progress: ArchiveTaskProgress?
    public let errorMessage: String?

    public init(
        requestID: UUID,
        kind: Kind,
        descriptor: ArchiveFormatDescriptor? = nil,
        entries: [ArchiveEntry]? = nil,
        archiveComment: String? = nil,
        progress: ArchiveTaskProgress? = nil,
        errorMessage: String? = nil
    ) {
        self.requestID = requestID
        self.kind = kind
        self.descriptor = descriptor
        self.entries = entries
        self.archiveComment = archiveComment
        self.progress = progress
        self.errorMessage = errorMessage
    }
}

public protocol ArchiveWorkerTransport: Sendable {
    func send(_ request: WorkerRequest, onEvent: @escaping @Sendable (WorkerResponse) -> Void) async throws
}

// MARK: - XPC Client Transport

public final class XPCWorkerClientTransport: NSObject, ArchiveWorkerTransport, PureZipWorkerXPCEventSinkProtocol, @unchecked Sendable {
    public static let defaultServiceName = "com.minato.purezip.ArchiveService"

    public let serviceName: String
    private let lock = NSLock()
    private var eventHandlers: [UUID: @Sendable (WorkerResponse) -> Void] = [:]

    public init(serviceName: String = XPCWorkerClientTransport.defaultServiceName) {
        self.serviceName = serviceName
        super.init()
    }

    public func receive(_ eventData: Data) {
        guard let response = try? JSONDecoder().decode(WorkerResponse.self, from: eventData) else {
            return
        }
        lock.lock()
        let handler = eventHandlers[response.requestID]
        lock.unlock()
        handler?(response)
    }

    private func setEventHandler(for id: UUID, handler: (@Sendable (WorkerResponse) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        if let handler {
            eventHandlers[id] = handler
        } else {
            eventHandlers.removeValue(forKey: id)
        }
    }

    public func send(_ request: WorkerRequest, onEvent: @escaping @Sendable (WorkerResponse) -> Void) async throws {
        let requestData = try JSONEncoder().encode(request)
        setEventHandler(for: request.requestID, handler: onEvent)
        defer {
            setEventHandler(for: request.requestID, handler: nil)
        }

        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: PureZipWorkerXPCProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: PureZipWorkerXPCEventSinkProtocol.self)
        connection.exportedObject = self
        connection.resume()
        defer { connection.invalidate() }

        let responsesData: Data = try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? PureZipWorkerXPCProtocol

            guard let proxy else {
                continuation.resume(throwing: CocoaError(.xpcConnectionInterrupted))
                return
            }

            proxy.submit(requestData) { replyData, replyError in
                if let replyError {
                    continuation.resume(throwing: replyError)
                } else if let replyData {
                    continuation.resume(returning: replyData)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }

        if !responsesData.isEmpty,
           let batched = try? JSONDecoder().decode([WorkerResponse].self, from: responsesData) {
            for ev in batched {
                onEvent(ev)
            }
        }
    }
}
