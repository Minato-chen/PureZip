import Foundation
import ArchiveCore
import ArchiveEngines

private final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [WorkerResponse] = []

    func append(_ response: WorkerResponse) {
        lock.lock()
        responses.append(response)
        lock.unlock()
    }

    func snapshot() -> [WorkerResponse] {
        lock.lock()
        defer { lock.unlock() }
        return responses
    }
}

/// XPC connection endpoint dispatching requests to `ArchiveWorkerRequestExecutor`.
final class WorkerConnectionEndpoint: NSObject, PureZipWorkerXPCProtocol, @unchecked Sendable {
    private let executor: ArchiveWorkerRequestExecutor
    private weak var connection: NSXPCConnection?
    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var isInvalidated = false

    init(executor: ArchiveWorkerRequestExecutor, connection: NSXPCConnection?) {
        self.executor = executor
        self.connection = connection
        super.init()
    }

    func submit(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        let request: WorkerRequest
        do {
            request = try JSONDecoder().decode(WorkerRequest.self, from: requestData)
        } catch {
            reply(nil, error as NSError)
            return
        }

        let exec = self.executor
        let reqID = request.requestID
        let collector = ResponseCollector()

        let task = Task { [weak self] in
            let endpoint = self
            await exec.execute(request) { response in
                collector.append(response)
                endpoint?.forwardEvent(response)
            }

            endpoint?.removeTask(for: reqID)
            let snapshot = collector.snapshot()

            do {
                let encoded = try JSONEncoder().encode(snapshot)
                reply(encoded, nil)
            } catch {
                reply(nil, error as NSError)
            }
        }

        lock.lock()
        tasks[reqID] = task
        lock.unlock()
    }

    func cancel(_ requestID: NSUUID) {
        let uuid = requestID as UUID
        lock.lock()
        let task = tasks.removeValue(forKey: uuid)
        lock.unlock()
        task?.cancel()
    }

    func invalidate(withReply reply: @escaping () -> Void) {
        lock.lock()
        isInvalidated = true
        let running = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()

        for t in running {
            t.cancel()
        }
        Task {
            await executor.shutdown()
            reply()
        }
    }

    private func removeTask(for id: UUID) {
        lock.lock()
        tasks.removeValue(forKey: id)
        lock.unlock()
    }

    private func forwardEvent(_ response: WorkerResponse) {
        if let data = try? JSONEncoder().encode(response),
           let sink = connection?.remoteObjectProxy as? PureZipWorkerXPCEventSinkProtocol {
            sink.receive(data)
        }
    }
}

/// NSXPCListener delegate configuring worker connections for `PureZipArchiveService`.
final class WorkerServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let executor = ArchiveWorkerRequestExecutor()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PureZipWorkerXPCProtocol.self)
        newConnection.remoteObjectInterface = NSXPCInterface(with: PureZipWorkerXPCEventSinkProtocol.self)
        let endpoint = WorkerConnectionEndpoint(executor: executor, connection: newConnection)
        newConnection.exportedObject = endpoint
        newConnection.resume()
        return true
    }
}

@main
struct PureZipArchiveServiceMain {
    static func main() async {
        if CommandLine.arguments.contains("--self-check") {
            let endpoint = WorkerConnectionEndpoint(executor: ArchiveWorkerRequestExecutor(), connection: nil)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                endpoint.invalidate {
                    continuation.resume()
                }
            }
            print("PureZipArchiveService XPC Worker ready (protocol: PureZipWorkerXPCProtocol)")
            return
        }

        let delegate = WorkerServiceDelegate()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        dispatchMain()
    }
}
