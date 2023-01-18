# SwiftWebConnect

SwiftWebConnect is a lightweight web-socket client framework written purely on Swift. It uses a minimalist interface and implements the latest Foundation features, avoiding any 3rd party dependency. It also uses error throwing and Apple's Combine for react-ness.

## How to use?

Using the frameworks is very easy. Since it is a socket-based program, you will need to access to the shared instance created at `.shared` static method. It will return the main instance, then you can interact with it.

```swift 
let client = SwiftWebSocket.shared

/// See: Conectable protocol.

client.configure() // (Optional) calls to the configuration method.
client.connect(url: URL) // Connects to a given non-optional URL.
client.disconnect() // Closes the socket and cleans up memory.

// Helper connection:
try client.connect(string: "ws:127.0.0.1:3000") // Connects to a given string based url.

/// See: Subscribable protocol.

let publisher = try client.subscribe()
publisher.sink { completion in
    // Do something on completion (.finished, .failure(Error))
} receiveValue: { data in
    // Arrived some data ...
}

// Note that you can use all Combine features with this method, due it returns a PassthroughSubject. See: .map(), .assign(), .store(), .cancel(), etc...

// We also deliver a convenience method for use just a Closure:
try sut.subscribe(onNext: { result in
    // Arrive some result ...
    // Note that result is Result<Data, Error> 
})

```

## Technical Documentation

The framework uses URLSession capabilities behind the scenes, we decoupled the Fondation's classes using a custom protocol that generalizes the interface as required.
