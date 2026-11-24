#if os(macOS)
import Foundation
import Testing
@testable import NekularityKit

private final class ServiceHTTPFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.absoluteString == "https://service-bridge.example.test/account",
              request.httpMethod == "GET",
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"id":10,"username":"from-host"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Test func installedServiceUsesCoreHostAndAnExplicitGrant() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "nk-service-test-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let defaults = try #require(UserDefaults(suiteName: root.lastPathComponent))
    defer { defaults.removePersistentDomain(forName: root.lastPathComponent) }
    let manifest = #"{"id":"service.bangumi","name":"Fixture","version":"1","kind":"service.js","entry":"index.mjs","permissions":["network","secrets","storage"]}"#
    let source = """
    export function handle(method, text) {
      if (secret('token') !== 'core-fixture-token') throw new Error('expected the scoped token');
      if (method === 'write') { storageSet('credential', secret('token')); return null; }
      if (method !== 'account.me' || JSON.parse(text) !== null) throw new Error('wrong request');
      return JSON.parse(fetch('https://service-bridge.example.test/account'));
    }
    """
    try Data(manifest.utf8).write(to: root.appending(path: "service.json"))
    try Data(source.utf8).write(to: root.appending(path: "index.mjs"))
    let zip = Process()
    zip.executableURL = URL(filePath: "/usr/bin/zip")
    zip.currentDirectoryURL = root
    zip.arguments = ["-q", "fixture.zip", "service.json", "index.mjs"]
    try zip.run()
    zip.waitUntilExit()
    try #require(zip.terminationStatus == 0)

    let cookies = CookieJars(file: nil)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServiceHTTPFixture.self]
    let transport = URLSessionTransport(cookies: cookies, defaultUserAgent: "test", configuration: configuration)
    let host = CoreHost(store: try SourceStore(root: root), cookies: cookies, transport: transport)
    let accounts = MemoryServiceAccounts()
    let id = KnownServiceID.bangumi
    try accounts.set(service: id, key: "token", value: "core-fixture-token")
    let store = ServiceStore(directory: root.appending(path: "services-root"), host: host,
                             accounts: accounts, defaults: defaults)
    await store.install(from: root.appending(path: "fixture.zip"))
    let record = try #require(store.records.first, "\(store.error ?? "")")
    let bridge = store.makeBridge()
    await #expect(throws: ServiceBridgeError.permissionDenied(service: id, missing: ["network", "secrets"])) {
        try await bridge.invokeIfInstalled(id, method: "account.me", secretKeys: ["token"], as: BangumiUser.self)
    }
    store.setStructuredAccess(true, for: record)
    let user = try await bridge.invokeIfInstalled(id, method: "account.me", secretKeys: ["token"], as: BangumiUser.self)
    #expect(user?.username == "from-host")
    await #expect(throws: ServiceBridgeError.executionFailed(service: id, method: "write")) {
        try await bridge.invokeIfInstalled(id, method: "write", secretKeys: ["token"], as: ServiceAcknowledgement.self)
    }
    store.remove(id)
    #expect(try await !bridge.installed(id))
    #expect(try accounts.values(service: id).isEmpty)
}
#endif
