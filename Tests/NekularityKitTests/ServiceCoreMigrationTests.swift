#if os(macOS)
import Foundation
import Testing
@testable import NekularityKit

private final class ServiceHTTPFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == "service-bridge.example.test",
              request.value(forHTTPHeaderField: "Authorization") == "Bearer core-fixture-token" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let status: Int
        let body: String
        switch (request.httpMethod, url.path) {
        case ("GET", "/account"):
            status = 200
            body = #"{"id":10,"username":"from-host"}"#
        case ("PATCH", "/episode"):
            let expected = Data(#"{"type":2}"#.utf8)
            status = requestBody() == expected && request.value(forHTTPHeaderField: "Content-Type") == "application/json" ? 202 : 400
            body = ""
        default:
            status = 405
            body = ""
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func requestBody() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 128)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { return result }
            result.append(contentsOf: buffer.prefix(count))
        }
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
      const token = secret('access_token');
      if (method === 'write') { storageSet('credential', token); return null; }
      const headers = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
      const base = 'https://service-bridge.example.test';
      if (method === 'episode.update') {
        const response = fetch(base + '/episode', { method: 'PATCH', headers, body: text });
        if (!response.ok || response.status !== 202) throw new Error('expected HTTP 202');
        return { ok: true, service: 'service.bangumi', method, data: { updated: true } };
      }
      if (method !== 'account.me' || JSON.parse(text) !== null) throw new Error('wrong request');
      const response = fetch(base + '/account', { method: 'GET', headers });
      if (!response.ok || response.status !== 200) throw new Error('expected HTTP 200');
      return { ok: true, service: 'service.bangumi', method, data: JSON.parse(response.text()) };
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
    try accounts.set(service: id, key: "access_token", value: "core-fixture-token")
    let store = ServiceStore(directory: root.appending(path: "services-root"), host: host,
                             accounts: accounts, defaults: defaults)
    await store.install(from: root.appending(path: "fixture.zip"))
    let record = try #require(store.records.first, "\(store.error ?? "")")
    let bridge = store.makeBridge(requireAuthorization: false)
    let preferred = store.makeBridge()
    #expect(try await preferred.installed(id) == false)
    await #expect(throws: ServiceBridgeError.permissionDenied(service: id, missing: ["network", "secrets"])) {
        try await bridge.invokeIfInstalled(id, method: "account.me", secretKeys: ["access_token"], as: BangumiUser.self)
    }
    store.setStructuredAccess(true, for: record)
    #expect(try await preferred.installed(id))
    let user = try await bridge.invokeIfInstalled(id, method: "account.me", secretKeys: ["access_token"], as: BangumiUser.self)
    #expect(user?.username == "from-host")
    let accepted = try await bridge.invokeIfInstalled(id, method: "episode.update",
                                                       payload: .serviceArguments(("type", .integer(2))),
                                                       secretKeys: ["access_token"], as: ServiceAcknowledgement.self)
    #expect(accepted != nil)
    await #expect(throws: ServiceBridgeError.executionFailed(service: id, method: "write")) {
        try await bridge.invokeIfInstalled(id, method: "write", secretKeys: ["access_token"], as: ServiceAcknowledgement.self)
    }
    store.setStructuredAccess(false, for: record)
    #expect(try await preferred.installed(id) == false)
    store.remove(id)
    #expect(try await bridge.installed(id) == false)
    #expect(try accounts.values(service: id).isEmpty)
}
#endif
