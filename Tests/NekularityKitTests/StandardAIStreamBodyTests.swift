import Foundation
import Testing
@testable import NekularityKit

private func config(_ standard: StandardProtocol) -> StandardAIConfig {
    StandardAIConfig(protocol: standard, baseURL: "", model: "m", anthropicVersion: "2023-06-01", maxTokens: 64)
}

/// A streaming request has to say so in the body; the endpoints differ only in
/// which field carries the messages.
@Test func aStreamingBodySaysStream() throws {
    for standard in StandardProtocol.allCases {
        let body = try StandardAI.requestBody(config: config(standard), model: "m",
                                              messages: [StandardMessage(role: "user", content: "hi")],
                                              stream: true)
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(parsed["stream"] as? Bool == true, "\(standard) did not ask for a stream")
    }
}

/// Without the flag the body asks for a whole answer, which is what the ordinary
/// path sends.
@Test func aPlainBodyAsksForAWholeAnswer() throws {
    let body = try StandardAI.requestBody(config: config(.chat), model: "m",
                                          messages: [StandardMessage(role: "user", content: "hi")])
    let parsed = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    #expect(parsed["stream"] as? Bool == false)
}

/// The three protocols keep their own shape when streaming; only the flag moves.
@Test func aStreamingBodyKeepsItsProtocolShape() throws {
    let messages = [StandardMessage(role: "user", content: "hi")]
    let chat = try StandardAI.requestBody(config: config(.chat), model: "m", messages: messages, stream: true)
    let responses = try StandardAI.requestBody(config: config(.responses), model: "m", messages: messages, stream: true)
    let anthropic = try StandardAI.requestBody(config: config(.messages), model: "m", messages: messages, stream: true)
    #expect(chat.contains("\"messages\""))
    #expect(responses.contains("\"input\""))
    #expect(anthropic.contains("\"max_tokens\""))
}
