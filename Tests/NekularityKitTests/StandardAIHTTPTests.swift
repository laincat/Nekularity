import Foundation
import Testing
@testable import NekularityKit

/// Real Core and URLSessionTransport, with URLProtocol replacing the network.
/// Every request has its own host and temporary store; no Keychain is used.
@Suite("Standard AI HTTP responses")
struct StandardAIHTTPTests {
    private func client(_ standard: StandardProtocol, status: Int, body: String,
                        models: Bool = false) throws -> (StandardAI, StandardAIConfig, URL, String) {
        let hostName = "ai-\(UUID().uuidString.lowercased()).test"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-\(UUID().uuidString)")
        let config = StandardAIConfig(protocol: standard, baseURL: "https://\(hostName)/v1", model: "fixture-model")
        let endpoint: String
        switch standard {
        case .chat: endpoint = "chat/completions"
        case .responses: endpoint = "responses"
        case .messages: endpoint = "messages"
        }
        let url = URL(string: config.baseURL + "/" + (models ? "models" : endpoint))!
        TransportStub.reply(url.absoluteString, with: .init(status: status,
                            headers: ["Content-Type": "application/json"], body: Data(body.utf8)))
        let jars = CookieJars(file: nil)
        jars.save(partition: StandardAI.partition, url: url,
                  cookies: [WireCookie(name: "must-not-send", value: "fixture")])
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [TransportStub.self]
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "ai-tests/1", configuration: session)
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: "1.0", locale: "zh_CN",
                                                     defaultUserAgent: "ai-tests/1"), host: host)
        return (StandardAI(core: core), config, root, hostName)
    }

    private func successfulBody(_ standard: StandardProtocol) -> String {
        switch standard {
        case .chat: #"{"choices":[{"message":{"role":"assistant","content":"fixture answer"}}]}"#
        case .responses: #"{"output":[{"type":"message","content":[{"type":"output_text","text":"fixture answer"}]}]}"#
        case .messages: #"{"content":[{"type":"text","text":"fixture answer"}]}"#
        }
    }

    @Test func successfulRepliesUseTheExpectedCredentialsWithoutCookies() async throws {
        for standard in StandardProtocol.allCases {
            let (api, config, root, host) = try client(standard, status: 200, body: successfulBody(standard))
            defer { try? FileManager.default.removeItem(at: root) }
            let reply = try await api.reply(config: config, apiKey: "fixture-key",
                                            messages: [StandardMessage(role: "user", content: "hi")])
            #expect(reply.text == "fixture answer")
            #expect(reply.status == 200)
            #expect(!reply.streamed)
            let requests = TransportStub.requests(host: host)
            #expect(requests.count == 1)
            let headers = try #require(requests.first?.headers)
            #expect(headers.first { $0.key.lowercased() == "cookie" } == nil)
            let name = standard == .messages ? "x-api-key" : "authorization"
            let expected = standard == .messages ? "fixture-key" : "Bearer fixture-key"
            #expect(headers.first { $0.key.lowercased() == name }?.value == expected)
        }
    }

    /// A rejected request never becomes an answer.
    ///
    /// Core classifies a provider failure without retaining the provider's own
    /// words (`aiapi.ClassifyHTTPResponse`): the message Core hands back is one
    /// of its fixed sentences, so an upstream body that quotes a key cannot
    /// travel through the bridge into a log or a bug report. The kit therefore
    /// reports the status and Core's classification, and must not surface the
    /// provider's text.
    @Test func HTTPFailuresCannotBecomeAssistantReplies() async throws {
        for standard in StandardProtocol.allCases {
            for status in [401, 503] {
                let body = status == 401 ? #"{"error":{"message":"invalid fixture key"}}"# : "unavailable"
                let (api, config, root, _) = try client(standard, status: status, body: body)
                defer { try? FileManager.default.removeItem(at: root) }
                do {
                    _ = try await api.reply(config: config, apiKey: "fixture-key",
                                            messages: [StandardMessage(role: "user", content: "hi")])
                    Issue.record("HTTP \(status) returned a normal \(standard) assistant reply")
                } catch let error as StandardAIError {
                    #expect(error.message.contains("HTTP \(status)"))
                    // Core's classification, not the fixture provider's sentence.
                    #expect(!error.message.contains("invalid fixture key"))
                    let lower = error.message.lowercased()
                    if status == 401 {
                        #expect(lower.contains("api key") || lower.contains("auth"),
                                "HTTP 401 should read as an auth failure: \(error.message)")
                    }
                }
            }
        }
    }

    /// An error envelope inside HTTP 200 is still a failure, and is classified
    /// the same way: the provider's own wording stays upstream.
    @Test func providerErrorsInsideHTTP200AreFailures() async throws {
        for standard in StandardProtocol.allCases {
            let (api, config, root, _) = try client(standard, status: 200,
                                                   body: #"{"error":{"message":"fixture rate limit"}}"#)
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                _ = try await api.reply(config: config, apiKey: "fixture-key",
                                        messages: [StandardMessage(role: "user", content: "hi")])
                Issue.record("an in-band \(standard) provider error became an assistant reply")
            } catch let error as StandardAIError {
                #expect(!error.message.contains("fixture rate limit"))
                #expect(error.message.lowercased().contains("rate limit"),
                        "an in-band provider error should read as a rate limit: \(error.message)")
            }
        }
    }

    @Test func catalogsListModelsAndRejectHTTPFailures() async throws {
        for standard in StandardProtocol.allCases {
            for status in [200, 403] {
                let (api, config, root, _) = try client(standard, status: status,
                         body: #"{"data":[{"id":"fixture-model"},{"id":"fixture-alt"}]}"#, models: true)
                defer { try? FileManager.default.removeItem(at: root) }
                do {
                    let models = try await api.models(config: config, apiKey: "fixture-key")
                    if status == 200 {
                        #expect(models == ["fixture-model", "fixture-alt"])
                    } else {
                        Issue.record("a rejected model catalog became a successful list")
                    }
                } catch let error as StandardAIError {
                    #expect(status == 403)
                    #expect(error.message.contains("HTTP 403"))
                }
            }
        }
    }
}
