import Foundation

/// Тестовый URLProtocol — подменяет ответ для любого URLRequest.
///
/// Использование:
///   MockURLProtocol.responder = { req in
///     return (HTTPURLResponse(...), Data(...))
///   }
///   let config = URLSessionConfiguration.ephemeral
///   config.protocolClasses = [MockURLProtocol.self]
///   let session = URLSession(configuration: config)
final class MockURLProtocol: URLProtocol {
    /// (response, data) — оба обязательны. Если бросаешь — клиент получит transport error.
    nonisolated(unsafe) static var responder: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Заглядывание для тестов (последний запрос).
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.lastBody = request.httpBody ?? request.bodyStreamData()

        guard let responder = MockURLProtocol.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// httpBodyStream → Data. URLSession превращает body в stream при отправке.
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
