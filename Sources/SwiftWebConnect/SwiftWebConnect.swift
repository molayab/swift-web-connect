import Foundation
import Combine

@available(macOS 10.15, *)
public protocol URLSessionProtocol {
    func socketTask(with url: URL) -> URLSessionWebSocketTaskProtocol?
}

@available(macOS 10.15, *)
public protocol URLSessionWebSocketTaskProtocol {
    func resume()
    func cancel(with: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
}

@available(macOS 10.15, *)
extension URLSession: URLSessionProtocol {
    public func socketTask(with url: URL) -> URLSessionWebSocketTaskProtocol? {
        return webSocketTask(with: url)
    }
}

@available(macOS 10.15, *)
extension URLSessionWebSocketTask: URLSessionWebSocketTaskProtocol { }

public protocol Connectable {
    var isConnected: Bool { get }
    
    func connect(string: String) throws
    func connect(url: URL)
    func disconnect()
}

@available(macOS 10.15, *)
public protocol Subscribable {
    func subscribe() throws -> PassthroughSubject<Data, Swift.Error>
    func subscribe(onNext: @escaping (Result<Data, Swift.Error>) -> Void) throws
}

@available(macOS 10.15, *)
public protocol SwiftWebConnectProtocol: Subscribable & Connectable {
    static var shared: SwiftWebConnect { get }
}

@available(macOS 10.15, *)
public final class SwiftWebConnect: NSObject, SwiftWebConnectProtocol {
    public static let shared = SwiftWebConnect()
    
    private var cancellables: [AnyCancellable] = []
    private var webSocket: URLSessionWebSocketTaskProtocol?
    private let operationQueue: OperationQueue = .init()
    private var session: URLSessionProtocol!
    private var continuos: Bool = true
    
    public private(set) var status: Status = .disconnected

    private override init() {
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
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        cancellables.forEach { $0.cancel() }
        status = .disconnected
        cancellables = []
    }
    
    public func subscribe() throws -> PassthroughSubject<Data, Swift.Error> {
        guard isConnected else {
            throw Error.notConnected
        }
        
        let subject = PassthroughSubject<Data, Swift.Error>()
        Task {
            readAndPublish(using: subject)
        }
        return subject
    }
    
    public func subscribe(onNext: @escaping (Result<Data, Swift.Error>) -> Void) throws {
        try subscribe().sink { completion in
            switch completion {
            case .failure(let error):
                onNext(.failure(error))
            case .finished: break
            }
        } receiveValue: { data in
            onNext(.success(data))
        }.store(in: &cancellables)
    }
    
    private func readAndPublish(using publisher: PassthroughSubject<Data, Swift.Error>) {
        let continuos = self.continuos
        
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let str):
                    if let data = str.data(using: .unicode) {
                        publisher.send(data)
                    } else {
                        publisher.send(
                            completion: .failure(Error.cannotConvertStringToUnicodeData))
                    }
                case .data(let data):
                    publisher.send(data)
                @unknown default:
                    fatalError()
                }
                
                if continuos {
                    self?.readAndPublish(using: publisher)
                } else {
                    publisher.send(completion: .finished)
                }
            case .failure(let error):
                publisher.send(completion: .failure(error))
            }
        }
    }
}

@available(macOS 10.15, *)
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

@available(macOS 10.15, *)
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
