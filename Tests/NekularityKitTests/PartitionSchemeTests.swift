import Foundation
import Testing
@testable import NekularityKit

/// The transport remembers the scheme each partition used, so a source that
/// serves its pages over http keeps its images over http.
@Suite("partition schemes")
struct PartitionSchemeTests {
    private func transport() -> URLSessionTransport {
        let jars = CookieJars(file: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SchemeStub.self]
        return URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1",
                                  timeout: 5, configuration: config)
    }

    private func request(_ url: String, id: Int64 = 1, partition: String = "comic:test") -> URLSessionTransport.Request {
        URLSessionTransport.Request(id: id, method: "GET", url: URL(string: url)!,
                                    headers: [:], body: nil, useCookies: true, partition: partition)
    }

    /// A partition that has not asked for anything yet has no scheme.
    @Test func anUnusedPartitionHasNoScheme() async {
        let t = transport()
        #expect(t.scheme(partition: "comic:nothing") == "")
    }

    /// After a request, the partition's scheme is known.
    @Test func aRequestTeachesThePartitionItsScheme() async throws {
        let t = transport()
        _ = try await t.send(request("http://plain.test/a", partition: "comic:plain"))
        #expect(t.scheme(partition: "comic:plain") == "http")
    }

    /// Two partitions keep their own schemes: one source over http and another
    /// over https must not change each other's images.
    @Test func partitionsKeepTheirOwnSchemes() async throws {
        let t = transport()
        _ = try await t.send(request("http://plain.test/a", partition: "comic:plain"))
        _ = try await t.send(request("https://secure.test/a", partition: "comic:secure"))
        #expect(t.scheme(partition: "comic:plain") == "http")
        #expect(t.scheme(partition: "comic:secure") == "https")
    }
}

/// Answers every request with an empty body.
final class SchemeStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "0"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
