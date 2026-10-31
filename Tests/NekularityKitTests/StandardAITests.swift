import Foundation
import Testing
@testable import NekularityKit

@Suite struct StandardAITests {
    private func answer(_ body: String) -> StandardAIAnswer {
        StandardAIAnswer(status: 200, headers: [:], bodyBase64: Data(body.utf8).base64EncodedString(),
                         finalUrl: "https://api.openai.com/v1/chat/completions", streamed: false)
    }

    @Test func chatTextIsExtracted() {
        let body = #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#
        #expect(StandardAI.text(from: answer(body), protocol: .chat) == "你好")
    }

    @Test func anthropicTextIsExtracted() {
        let body = #"{"content":[{"type":"text","text":"第一"},{"type":"tool_use","id":"x"},{"type":"text","text":"第二"}]}"#
        #expect(StandardAI.text(from: answer(body), protocol: .messages) == "第一第二")
    }

    @Test func responsesTextIsExtracted() {
        let direct = #"{"output_text":"直接"}"#
        #expect(StandardAI.text(from: answer(direct), protocol: .responses) == "直接")
        let nested = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"嵌套"}]}]}"#
        #expect(StandardAI.text(from: answer(nested), protocol: .responses) == "嵌套")
    }

    /// An error carried in a 200 body must be shown as the error, not as an
    /// empty answer that looks like the model said nothing.
    @Test func anErrorInsideTheBodyIsShown() {
        let body = #"{"error":{"message":"invalid api key","type":"auth"}}"#
        #expect(StandardAI.text(from: answer(body), protocol: .chat) == "invalid api key")
    }

    /// A shape this version does not understand keeps the raw JSON rather than
    /// showing a blank panel.
    @Test func anUnknownShapeFallsBackToTheRawBody() {
        let body = #"{"unexpected":{"deep":[1,2]}}"#
        #expect(StandardAI.text(from: answer(body), protocol: .chat) == body)
    }

    @Test func modelIDsKeepTheOrderAndSkipEntriesWithoutAnID() throws {
        let data = Data(#"{"data":[{"id":"gpt-4o"},{"name":"no id"},{"id":"o3"}]}"#.utf8)
        let ids = try StandardAI.modelIDs(data)
        #expect(ids == ["gpt-4o", "o3"])
    }

    @Test func aCatalogThatIsNotJSONIsAnError() {
        #expect(throws: StandardAIError.self) { try StandardAI.modelIDs(Data("not json".utf8)) }
    }

    /// Anthropic refuses a request without max_tokens, so the body must carry
    /// one; the other protocols must not invent it.
    @Test func theBodyMatchesTheProtocol() throws {
        var config = StandardAIConfig(protocol: .messages)
        config.maxTokens = 512
        let messages = [StandardMessage(role: "user", content: "hi")]
        let anthropic = try StandardAI.requestBody(config: config, model: "claude", messages: messages)
        #expect(anthropic.contains(#""max_tokens":512"#))
        #expect(anthropic.contains(#""stream":false"#))

        config = StandardAIConfig(protocol: .chat)
        let chat = try StandardAI.requestBody(config: config, model: "gpt", messages: messages)
        #expect(!chat.contains("max_tokens"))
        #expect(chat.contains(#""messages""#))

        config = StandardAIConfig(protocol: .responses)
        let responses = try StandardAI.requestBody(config: config, model: "gpt", messages: messages)
        #expect(responses.contains(#""input""#))
        #expect(!responses.contains(#""messages""#))
    }

    @Test func theWireConfigCarriesThePartitionAndOmitsEmptyFields() throws {
        var config = StandardAIConfig(protocol: .chat, model: "gpt")
        let json = try config.wireJSON(apiKey: "sk-test")
        #expect(json.contains(#""protocol":"chat""#))
        #expect(json.contains(#""partition":"ai""#))
        #expect(!json.contains("baseUrl"))
        #expect(!json.contains("anthropicVersion"))

        config.baseURL = "https://gateway.example/openai"
        config.anthropicVersion = "2024-10-22"
        let explicit = try config.wireJSON(apiKey: "sk-test")
        #expect(explicit.contains("gateway.example"))
        #expect(explicit.contains("2024-10-22"))
    }

    @Test func anEmptyAddressUsesTheVendorDefault() {
        #expect(StandardAIConfig(protocol: .chat).effectiveBaseURL == "https://api.openai.com/v1")
        #expect(StandardAIConfig(protocol: .messages).effectiveBaseURL == "https://api.anthropic.com/v1")
        #expect(StandardAIConfig(protocol: .chat, baseURL: "  ").effectiveBaseURL == "https://api.openai.com/v1")
    }

    /// The settings file holds no key: it must survive a round trip without one.
    @Test func settingsRoundTripWithoutAKey() {
        let defaults = UserDefaults(suiteName: "std-\(UUID().uuidString)")!
        let store = StandardAISettingsStore(defaults: defaults)
        var config = StandardAIConfig(protocol: .responses, baseURL: "https://x.test/v1", model: "m")
        config.maxTokens = 128
        store.save(config)
        let loaded = store.load()
        #expect(loaded == config)
        #expect(!String(describing: loaded).contains("sk-"))
    }
}
