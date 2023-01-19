import XCTest
import Combine
@testable import SwiftWebConnect

struct URLSessionMock: URLSessionProtocol {
    var onSocketTask: URLSessionWebSocketTaskMock?
    
    func socketTask(with url: URL) -> URLSessionWebSocketTaskProtocol? {
        return onSocketTask
    }
}

struct URLSessionWebSocketTaskMock: URLSessionWebSocketTaskProtocol {
    var onResume: () -> Void
    var onCancel: (URLSessionWebSocketTask.CloseCode, Data?) -> Void
    var onReceiveSend: Result<URLSessionWebSocketTask.Message, Error>
    
    func resume() {
        onResume()
    }
    
    func cancel(with: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onCancel(with, reason)
    }
    
    func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        completionHandler(onReceiveSend)
    }
}

final class SwiftWebConnectTests: XCTestCase {
    var cancellables: [AnyCancellable] = []
    
    func testSuccessConnection() throws {
        // GIVEN
        let sut = SwiftWebConnect()
        var wasCalledOnResume = false
        let mock = URLSessionWebSocketTaskMock(
            onResume: { wasCalledOnResume.toggle() },
            onCancel: { (_, _) in },
            onReceiveSend: .success(.data(Data())))
        let mock2 = URLSessionMock(onSocketTask: mock)
        sut.configure(session: mock2, continuos: false)
        
        // WHEN
        sut.connect(url: URL(string: "http://example.com")!)
        
        // THEN
        XCTAssertTrue(wasCalledOnResume)
        XCTAssertTrue(sut.isConnected)
    }
    
    func testFailureConnection() throws {
        // GIVEN
        let sut = SwiftWebConnect()
        let mock2 = URLSessionMock(onSocketTask: nil)
        sut.configure(session: mock2, continuos: false)
        
        // WHEN
        sut.connect(url: URL(string: "http://example.com")!)
        
        // THEN
        XCTAssertFalse(sut.isConnected)
        guard case .failed(let e) = sut.status else {
            return XCTFail("Incorrect status for an error")
        }
        XCTAssertEqual(e, SwiftWebConnect.Error.cannotOpenWebSocketRequest)
    }
    
    func testInvalidUrlConnection() throws {
        // GIVEN
        let sut = SwiftWebConnect()
        let mock2 = URLSessionMock(onSocketTask: nil)
        sut.configure(session: mock2, continuos: false)
        
        // WHEN & THEN
        XCTAssertThrowsError(try sut.connect(string: "<*>"))
        do {
            try sut.connect(string: "<*>")
        } catch {
            XCTAssertEqual(error as! SwiftWebConnect.Error, .invalidUrl)
        }
    }
    
    func testSuccessSubscriptionClosure() throws {
        // GIVEN
        let sut = SwiftWebConnect()
        var receivedData: Result<Data, Error>?
        var calledOnResume: Bool = false
        
        let mock = URLSessionWebSocketTaskMock(
            onResume: { calledOnResume.toggle() },
            onCancel: { (_, _) in },
            onReceiveSend: .success(.string("Hello World")))
        let mock2 = URLSessionMock(onSocketTask: mock)
        
        sut.configure(session: mock2, continuos: false)
        try sut.connect(string: "mocked")
        
        // WHEN
        let exp2 = expectation(description: "Waiting for data")
        try sut.subscribe(onNext: { result in
            receivedData = result
            exp2.fulfill()
        })
        
        // THEN
        waitForExpectations(timeout: 2)
        
        XCTAssertNotNil(receivedData)
        XCTAssertTrue(calledOnResume)
        
        guard case .success(let data) = receivedData else {
            return XCTFail("Incorrect result for action")
        }
        XCTAssertEqual(data, "Hello World".data(using: .unicode))
    }
    
    func testSuccessSubscription() throws {
        // GIVEN
        let sut = SwiftWebConnect()
        var receivedData: Data?
        var calledOnResume: Bool = false
        
        let mock = URLSessionWebSocketTaskMock(
            onResume: { calledOnResume.toggle() },
            onCancel: { (_, _) in },
            onReceiveSend: .success(.string("Hello World")))
        let mock2 = URLSessionMock(onSocketTask: mock)
        
        sut.configure(session: mock2, continuos: false)
        try sut.connect(string: "mocked")
        
        // WHEN
        let publisher = try sut.subscribe()
        
        // THEN
        let exp = expectation(description: "Waiting publisher finishes")
        let exp2 = expectation(description: "Waiting for data")
        publisher.sink { completion in
            if case .failure = completion {
                return
            }
            exp.fulfill()
        } receiveValue: { data in
            receivedData = data
            exp2.fulfill()
        }.store(in: &cancellables)

        waitForExpectations(timeout: 2)
        
        XCTAssertNotNil(receivedData)
        XCTAssertTrue(calledOnResume)
        XCTAssertEqual(receivedData, "Hello World".data(using: .unicode))
    }
}
