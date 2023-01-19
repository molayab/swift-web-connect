import Foundation
import Combine

public protocol URLSessionProtocol {
    func socketTask(with url: URL) -> URLSessionWebSocketTaskProtocol?
}

public protocol URLSessionWebSocketTaskProtocol {
    func resume()
    func cancel(with: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void)
}

extension URLSession: URLSessionProtocol {
    public func socketTask(with url: URL) -> URLSessionWebSocketTaskProtocol? {
        return webSocketTask(with: url)
    }
}

extension URLSessionWebSocketTask: URLSessionWebSocketTaskProtocol { }

public protocol Connectable {
    var isConnected: Bool { get }
    
    func connect(string: String) throws
    func connect(url: URL)
    func disconnect()
}

public protocol Subscribable {
    func subscribe() throws -> PassthroughSubject<Data, Swift.Error>
    func subscribe(onNext: @escaping (Result<Data, Swift.Error>) -> Void) throws
}

public protocol SwiftWebConnectProtocol: Subscribable & Connectable {
    static var shared: SwiftWebConnect { get }
}

public final class SwiftWebConnect: NSObject, SwiftWebConnectProtocol {
    public static let shared = SwiftWebConnect()
    
    private var cancellables: [AnyCancellable] = []
    private var webSocket: URLSessionWebSocketTaskProtocol?
    private let operationQueue: OperationQueue = .init()
    private var session: URLSessionProtocol!
    private var continuos: Bool = true
    
    public private(set) var status: Status = .disconnected

    override init() {
        super.init()
        operationQueue.maxConcurrentOperationCount = 1
        configure()
    }
    
    public var isConnected: Bool {
        guard case .connected = status else {
            return false
        }
        
        return true
    }
    
    public func configure() {
        configure(
            session: URLSession(
                configuration: .default,
                delegate: self,
                delegateQueue: operationQueue))
    }
    
    public func configure(session: URLSessionProtocol, continuos: Bool = true) {
        self.session = session
        self.continuos = continuos
    }
    
    public func connect(string: String) throws {
        guard let url = URL(string: string) else {
            throw Error.invalidUrl
        }
        
        connect(url: url)
    }
    
    public func connect(url: URL) {
        self.webSocket = session.socketTask(with: url)
        if let webSocket = self.webSocket {
            webSocket.resume()
            status = .connected
        } else {
            status = .failed(.cannotOpenWebSocketRequest)
        }
    }
    
    public func disconnect() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        status = .disconnected
    }
    
    public func subscribe() throws -> PassthroughSubject<Data, Swift.Error> {
        guard isConnected else {
            throw Error.notConnected
        }
        
        let subject = PassthroughSubject<Data, Swift.Error>()
        Task(priority: .low) {
            try await Task.sleep(for: .milliseconds(5))
            readAndPublish(subject)
        }
        return subject
    }
    
    public func subscribe(onNext: @escaping (Result<Data, Swift.Error>) -> Void) throws {
        let a = try subscribe()
            .sink { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    onNext(.failure(error))
                }
            } receiveValue: { data in
                onNext(.success(data))
            }
        a.store(in: &cancellables)
    }
    
    public func send(_ data: Data) async -> Result<Void, Swift.Error> {
        return await withCheckedContinuation { c in
            webSocket?.send(.data(data)) { error in
                if let error = error {
                    c.resume(returning: .failure(error))
                } else {
                    c.resume(returning: .success(()))
                }
            }
        }
    }
    
    public func send(string: String) async -> Result<Void, Swift.Error> {
        return await withCheckedContinuation { c in
            webSocket?.send(.string(string)) { error in
                if let error = error {
                    c.resume(returning: .failure(error))
                } else {
                    c.resume(returning: .success(()))
                }
            }
        }
    }
    
    private func readAndPublish(_ subject: PassthroughSubject<Data, Swift.Error>) {
        let continuos = self.continuos
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let str):
                    if let data = str.data(using: .unicode) {
                        subject.send(data)
                    } else {
                        subject.send(
                            completion: .failure(Error.cannotConvertStringToUnicodeData))
                    }
                case .data(let data):
                    subject.send(data)
                @unknown default:
                    fatalError()
                }
                
                if continuos {
                    self?.readAndPublish(subject)
                } else {
                    subject.send(completion: .finished)
                }
            case .failure(let error):
                subject.send(completion: .failure(error))
            }
        }
    }
}

extension SwiftWebConnect: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        // WebSocket is now open and confirmed by Foundation's url session.
        status = .connected
    }
    
    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?) {
        // WebSocket is now close and confirmed by Foundation's url session.
        status = .disconnected
    }
}

extension SwiftWebConnect {
    public typealias Reason = Error
    public enum Error: Swift.Error {
        case notConnected
        case invalidUrl
        case cannotOpenWebSocketRequest
        case cannotConvertStringToUnicodeData
    }
    
    public enum Status {
        case connected
        case disconnected
        case failed(Reason)
    }
}
