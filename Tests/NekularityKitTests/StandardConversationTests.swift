import Foundation
import Testing
@testable import NekularityKit

private func reply(_ text: String, streamed: Bool = false) -> StandardAIReply {
    StandardAIReply(status: 200, text: text, raw: "{}", streamed: streamed)
}

/// The answer lives in exactly one place: a screen that kept it both as a
/// `reply` and as the last message once drew the same answer twice.
@Test func anAnswerIsDrawnOnce() {
    var talk = StandardConversation()
    _ = talk.ask("你好")
    talk.answered(reply("第一段"))

    #expect(talk.pending?.text == "第一段")
    #expect(talk.messages.count == 1, "the answer must not also be in the message list")
    #expect(talk.turns.count == 2)
    #expect(talk.turns.filter { $0.role == "assistant" }.count == 1)
}

/// The question and the answer both go to the endpoint next time, in order.
@Test func theNextQuestionSendsBothSides() {
    var talk = StandardConversation()
    _ = talk.ask("你好")
    talk.answered(reply("第一段"))

    let history = talk.ask("再来一段")
    #expect(history.map(\.role) == ["user", "assistant", "user"])
    #expect(history.map(\.content) == ["你好", "第一段", "再来一段"])
    #expect(talk.pending == nil, "folding the answer in must clear the tail")
    #expect(talk.turns.count == 3)
}

/// A failed request leaves the question standing and no answer, so the error is
/// shown beside something the user asked.
@Test func aFailureLeavesTheQuestionOnly() {
    var talk = StandardConversation()
    _ = talk.ask("你好")
    talk.answered(reply("半截"))
    talk.failed()

    #expect(talk.pending == nil)
    #expect(talk.messages.map(\.role) == ["user"])
    #expect(talk.turns.count == 1)
}

/// Stopping keeps whatever arrived; the next question folds it into the record
/// rather than dropping it.
@Test func aStoppedAnswerIsKeptAsATurn() {
    var talk = StandardConversation()
    _ = talk.ask("你好")
    talk.answered(reply("到一半"))

    _ = talk.ask("继续")
    #expect(talk.messages.map(\.content) == ["你好", "到一半", "继续"])
}

/// Several turns in a row stay in order and never duplicate an answer.
@Test func severalTurnsKeepTheirOrder() {
    var talk = StandardConversation()
    for (question, answer) in [("一", "A"), ("二", "B"), ("三", "C")] {
        _ = talk.ask(question)
        talk.answered(reply(answer))
    }
    #expect(talk.turns.map(\.content) == ["一", "A", "二", "B", "三", "C"])
    #expect(Set(talk.turns.map(\.content)).count == talk.turns.count)
}
