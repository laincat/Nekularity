import Foundation
import Testing
@testable import NekularityKit

/// Dedicated `URLProtocol` stub for real Core adaptation bridge tests.
///
/// Keyed strictly by per-test unique host names and never reset globally so
/// parallel Swift Testing suites cannot interfere with one another.
final class AdaptTransportStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data()
        /// Optional pause before delivering so cancellation tests can cancel mid-flight.
        var holdForCancel: Bool = false
    }

    typealias Handler = @Sendable (URLRequest, Data) -> Reply

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var seen: [String: [(url: URL, headers: [String: String], body: Data)]] = [:]
    nonisolated(unsafe) private static var startedCallbacks: [String: @Sendable () -> Void] = [:]
    nonisolated(unsafe) private static var cancelledHosts: [String: Int] = [:]

    static func register(
        host: String,
        onStart: (@Sendable () -> Void)? = nil,
        handler: @escaping Handler
    ) {
        lock.lock(); defer { lock.unlock() }
        handlers[host] = handler
        if let onStart { startedCallbacks[host] = onStart }
    }

    static func requests(host: String) -> [(url: URL, headers: [String: String], body: Data)] {
        lock.lock(); defer { lock.unlock() }
        return seen[host] ?? []
    }

    static func cancelCount(host: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return cancelledHosts[host] ?? 0
    }

    private static func readBody(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            out.append(buffer, count: count)
        }
        return out
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var stopped = false
    private var hostName = ""

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        hostName = host
        let body = Self.readBody(from: request)
        let (handler, onStart): (Handler?, (@Sendable () -> Void)?) = Self.lock.withLock {
            Self.seen[host, default: []].append((url, request.allHTTPHeaderFields ?? [:], body))
            return (Self.handlers[host], Self.startedCallbacks[host])
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let reply = handler(request, body)
        onStart?()
        if reply.holdForCancel {
            // Stay open until `stopLoading()` is triggered by Core.Cancel -> URLSession cancellation.
            return
        }
        var headers = reply.headers
        headers["Content-Length"] = String(reply.body.count)
        let response = HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stopped = true
        let host = hostName
        guard !host.isEmpty else { return }
        Self.lock.withLock {
            Self.cancelledHosts[host, default: 0] += 1
        }
    }
}

private final class AdaptAtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
    var current: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

/// Exercises the real gomobile `CoreClient` bridge for `AdaptChapter`,
/// `RenderPanel`, and `RenderStoryboard` over `URLSessionTransport` + `AdaptTransportStub`.
@MainActor
@Suite("Adapt Core bridge", .serialized)
struct AdaptCoreBridgeTests {
    private static let pngBytes = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
        0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82,
    ])

    private func makeCore(seedCookieHost: String? = nil) throws -> (CoreClient, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nk-adapt-core-\(UUID().uuidString)")
        let jars = CookieJars(file: nil)
        if let seedCookieHost, let url = URL(string: "https://\(seedCookieHost)/v1/chat/completions") {
            jars.save(
                partition: StandardAI.partition,
                url: url,
                cookies: [WireCookie(name: "must_not_send", value: "forbidden")]
            )
        }
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [AdaptTransportStub.self]
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-adapt-test/1", configuration: session)
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(
            config: CoreConfig(appVersion: SourceAPI.level, locale: "zh_CN", defaultUserAgent: "nk-adapt-test/1"),
            host: host
        )
        return (core, root)
    }

    @Test func endToEndAdaptCheckpointResumeAndPanelRendering() async throws {
        let hostName = "adapt-\(UUID().uuidString.lowercased()).test"
        let (core, root) = try makeCore(seedCookieHost: hostName)
        defer { try? FileManager.default.removeItem(at: root) }

        let textCalls = AdaptAtomicCounter()
        let imageCalls = AdaptAtomicCounter()
        let pngB64 = Self.pngBytes.base64EncodedString()

        AdaptTransportStub.register(host: hostName) { request, _ in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/chat/completions") {
                let n = textCalls.increment()
                let content: String
                if n == 1 {
                    content = #"{"scenes":[{"setting":"Rainy street","panels":[{"shot":"wide","action":"Steps out","characters":["Wen"],"prompt":"rainy street"}]}],"newCharacters":[{"id":"c1","name":"Wen","appearance":"dark hair","outfit":"coat"}]}"#
                } else {
                    content = #"{"scenes":[{"setting":"Hallway","panels":[{"shot":"close","action":"Holds key","characters":["Wen"],"prompt":"brass key"}]}]}"#
                }
                let encodedContent = String(decoding: try! JSONEncoder().encode(content), as: UTF8.self)
                let body = #"{"choices":[{"message":{"content":\#(encodedContent)}}],"usage":{"prompt_tokens":50,"completion_tokens":30,"total_tokens":80}}"#
                return .init(status: 200, body: Data(body.utf8))
            }
            if path.contains(":generateContent") {
                let n = imageCalls.increment()
                if n == 2 {
                    // Second panel in RenderStoryboard is blocked by Gemini safety policy.
                    let blocked = #"{"candidates":[{"finishReason":"IMAGE_SAFETY","content":{"parts":[]}}]}"#
                    return .init(status: 200, body: Data(blocked.utf8))
                }
                let ok = #"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"\#(pngB64)"}}]}}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":8,"totalTokenCount":20}}"#
                return .init(status: 200, body: Data(ok.utf8))
            }
            return .init(status: 404, body: Data("not found".utf8))
        }

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("nk-adapt-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = NovelAdaptStore(directory: storeDir)
        let coordinator = NovelAdaptCoordinator(projectID: "e2e-proj", client: core, store: store)
        coordinator.ensureProject(title: "Rainy Night", budget: AdaptBudget(maxCalls: 1))

        let chapter = NovelChapter(id: "ch1", title: "Chapter 1")
        let content = NovelChapterContent(html: "<p>第一段：夜雨敲窗，少年推门而出。</p><p>第二段：走廊尽头微弱的灯光摇曳。</p>")
        let textConfig = AdaptTextConfig(
            protocol: .chat,
            baseURL: "https://\(hostName)/v1",
            apiKey: "sk-e2e-text-secret",
            model: "gpt-test",
            jsonMode: true
        )

        // 1. Pass 1 stops after chunk 1 due to MaxCalls=1 and persists checkpoint.
        let pass1 = try await coordinator.adaptChapter(chapter, content: content, textConfig: textConfig, maxChunkRunes: 18)
        #expect(!pass1.completed)
        #expect(pass1.parsedErrorCode == .budgetExceeded)
        #expect(pass1.result?.completedChunks == 1)
        #expect(textCalls.current == 1)
        #expect(coordinator.checkpoint(for: "ch1")?.completedChunks == 1)

        // Verify Cookies: false was enforced through real URLSessionTransport.
        let sentHeaders = AdaptTransportStub.requests(host: hostName).first?.headers ?? [:]
        #expect(sentHeaders.first { $0.key.lowercased() == "cookie" } == nil)

        // 2. Raise budget and resume -> skips chunk 1 and finishes with 2 total text calls.
        store.updateBudget(projectID: "e2e-proj", budget: AdaptBudget(maxCalls: 4))
        let pass2 = try await coordinator.adaptChapter(chapter, content: content, textConfig: textConfig)
        #expect(pass2.completed)
        #expect(textCalls.current == 2)
        #expect(coordinator.checkpoint(for: "ch1") == nil)
        #expect(coordinator.characters.map(\.name) == ["Wen"])
        let storyboard = try #require(coordinator.storyboard(for: "ch1"))
        #expect(storyboard.panelCount == 2)

        // 3. RenderStoryboard with continueOnError=true: p1 renders, p2 blocked (no retry).
        let imageConfig = AdaptImageConfig(
            provider: .gemini,
            baseURL: "https://\(hostName)/v1beta",
            apiKey: "gem-e2e-img-secret",
            model: "gemini-2.5-flash-image"
        )
        let sbResp = try await coordinator.renderStoryboard(
            chapterID: "ch1",
            imageConfig: imageConfig,
            options: AdaptRenderOptions(maxRetries: 2, continueOnError: true)
        )
        #expect(!sbResp.completed)
        #expect(sbResp.result.rendered == 1)
        #expect(sbResp.result.blocked == 1)
        #expect(sbResp.result.failures.first?.parsedErrorCode == .contentBlocked)
        #expect(imageCalls.current == 2)
        #expect(coordinator.panelImageData(chapterID: "ch1", sceneID: "s1", panelID: "p1") == Self.pngBytes)

        // 4. RenderPanel on already-done p1 without forceRerender skips with zero image calls.
        let skipped = try await coordinator.renderPanel(
            chapterID: "ch1",
            sceneID: "s1",
            panelID: "p1",
            imageConfig: imageConfig,
            forceRerender: false
        )
        #expect(skipped.skipped)
        #expect(imageCalls.current == 2)

        // 5. ForceRerender on p1 invokes Gemini again and refreshes cached bytes.
        let rerendered = try await coordinator.rerenderPanel(
            chapterID: "ch1",
            sceneID: "s1",
            panelID: "p1",
            imageConfig: imageConfig
        )
        #expect(!rerendered.skipped)
        #expect(imageCalls.current == 3)
        #expect(coordinator.panelImageData(chapterID: "ch1", sceneID: "s1", panelID: "p1") == Self.pngBytes)
    }

    @Test func contentBlockedSinglePanelRedactsKeyAndDoesNotRetry() async throws {
        let hostName = "adapt-blocked-\(UUID().uuidString.lowercased()).test"
        let (core, root) = try makeCore()
        defer { try? FileManager.default.removeItem(at: root) }

        let calls = AdaptAtomicCounter()
        let secret = "openai-secret-blocked-999"
        AdaptTransportStub.register(host: hostName) { _, _ in
            _ = calls.increment()
            let body = #"{"error":{"code":"content_policy_violation","message":"rejected for key \#(secret)"}}"#
            return .init(status: 400, body: Data(body.utf8))
        }

        let project = AdaptProject(
            id: "p-blocked",
            title: "Blocked",
            storyboards: [
                "ch1": AdaptStoryboard(chapterID: "ch1", scenes: [
                    AdaptScene(id: "s1", setting: "Room", panels: [
                        AdaptPanel(id: "p1", shot: "close", action: "Test", prompt: "test")
                    ])
                ])
            ]
        )

        do {
            _ = try await core.renderPanel(RenderPanelRequest(
                project: project,
                chapterID: "ch1",
                sceneID: "s1",
                panelID: "p1",
                image: AdaptImageConfig(
                    provider: .openai,
                    baseURL: "https://\(hostName)/v1",
                    apiKey: secret,
                    model: "gpt-image-1"
                ),
                options: AdaptRenderOptions(maxRetries: 3)
            ))
            Issue.record("expected content blocked error")
        } catch let error as CoreError {
            #expect(error.isContentBlocked, "unexpected error: \(error.message)")
            #expect(error.errorDescription == AdaptErrorCode.contentBlocked.readableMessage)
            #expect(!error.message.contains(secret))
            #expect(calls.current == 1)
        }
    }

    @Test func cancellationPropagatesViaCallIDAndInvalidArgsFailCleanly() async throws {
        let hostName = "adapt-cancel-\(UUID().uuidString.lowercased()).test"
        let (core, root) = try makeCore()
        defer { try? FileManager.default.removeItem(at: root) }

        let (startedStream, startedContinuation) = AsyncStream.makeStream(of: Int.self)
        AdaptTransportStub.register(host: hostName, onStart: {
            startedContinuation.yield(1)
            startedContinuation.finish()
        }) { _, _ in
            .init(status: 200, holdForCancel: true)
        }

        let task = Task {
            try await core.adaptChapter(AdaptChapterRequest(
                project: AdaptProject(id: "p-cancel", title: "Cancel"),
                chapter: NovelChapter(id: "ch1", title: "Ch1"),
                content: NovelChapterContent(html: "<p>Hello world.</p>"),
                text: AdaptTextConfig(
                    protocol: .chat,
                    baseURL: "https://\(hostName)/v1",
                    apiKey: "cancel-key",
                    model: "gpt-test"
                )
            ))
        }

        var iterator = startedStream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancelled adaptChapter")
        } catch let error as CoreError {
            #expect(error.isCancelled, "unexpected error: \(error.message)")
            #expect(error.errorDescription == "操作已取消")
        } catch is CancellationError {
            // Also acceptable if Swift cancelled before continuation resumed.
        }

        // Invalid parameters across all three entry points produce readable errors.
        do {
            _ = try await core.adaptChapter(AdaptChapterRequest(
                project: AdaptProject(id: "p1", title: "Empty key"),
                chapter: NovelChapter(id: "ch1", title: "Ch1"),
                content: NovelChapterContent(html: "<p>Text</p>"),
                text: AdaptTextConfig(protocol: .chat, apiKey: "", model: "gpt-test")
            ))
            Issue.record("expected missing apiKey error")
        } catch let error as CoreError {
            #expect(error.isInvalidAdaptArgument)
            #expect(error.errorDescription == "请先配置有效的模型 API Key")
        }

        do {
            _ = try await core.renderPanel(RenderPanelRequest(
                project: AdaptProject(id: "p1", title: "Missing panel"),
                chapterID: "ch1",
                panelID: "",
                image: AdaptImageConfig(provider: .gemini, apiKey: "k", model: "m")
            ))
            Issue.record("expected missing panelId error")
        } catch let error as CoreError {
            #expect(error.isInvalidAdaptArgument)
        }

        do {
            _ = try await core.renderStoryboard(RenderStoryboardRequest(
                project: AdaptProject(id: "p1", title: "Missing chapter"),
                chapterID: "",
                image: AdaptImageConfig(provider: .openai, apiKey: "k", model: "m")
            ))
            Issue.record("expected missing chapterId error")
        } catch let error as CoreError {
            #expect(error.isInvalidAdaptArgument)
        }
    }
}
