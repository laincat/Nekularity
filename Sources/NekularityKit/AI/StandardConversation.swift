import Foundation

/// The standard-protocol conversation: what was asked, what came back, and the
/// answer still sitting at the end.
///
/// The split exists because the view draws the last answer differently (it also
/// says whether it was streamed). Keeping that answer in two places — a `reply`
/// property *and* the message list — is what once drew the same answer twice;
/// here exactly one of them holds it at any moment.
public struct StandardConversation: Sendable, Equatable {
    /// Every finished turn, oldest first.
    public private(set) var messages: [StandardMessage]
    /// The answer to the newest question, until the next question folds it into
    /// `messages`.
    public private(set) var pending: StandardAIReply?

    public init(messages: [StandardMessage] = []) {
        self.messages = messages
    }

    /// What to send: every finished turn plus the question being asked.
    public var history: [StandardMessage] { messages }

    /// Records the question, first folding the previous answer in, and returns
    /// the history to send.
    public mutating func ask(_ text: String) -> [StandardMessage] {
        foldPending()
        messages.append(StandardMessage(role: "user", content: text))
        return messages
    }

    /// Takes the answer. It is not appended: it is the tail until the next
    /// question, which is what keeps it drawn once.
    public mutating func answered(_ reply: StandardAIReply) {
        pending = reply
    }

    /// The answer never arrived. The question stays, so the failure is shown
    /// beside something the user actually asked.
    public mutating func failed() {
        pending = nil
    }

    /// Everything the view draws, in order: finished turns, then the tail.
    public var turns: [StandardMessage] {
        if let pending {
            return messages + [StandardMessage(role: "assistant", content: pending.text)]
        }
        return messages
    }

    private mutating func foldPending() {
        guard let pending else { return }
        messages.append(StandardMessage(role: "assistant", content: pending.text))
        self.pending = nil
    }
}
