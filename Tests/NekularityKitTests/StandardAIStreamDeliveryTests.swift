import Foundation
import Testing
@testable import NekularityKit

/// Pieces of an answer reach the screen in the order they were written.
@MainActor
@Test func streamPiecesArriveInOrder() async {
    let runner = StandardAIRequest()
    var seen: [String] = []
    var finished = false
    let task = runner.startStream(operation: { emit in
        emit("Hel")
        emit("lo")
        return "Hello"
    }, receive: { _ in
        finished = true
    }, delta: { piece in
        seen.append(piece)
    }, failure: { _ in
        Issue.record("the stream failed")
    })
    await task.value

    // Deltas hop through the main actor, so give them a moment to land.
    for _ in 0..<50 where seen.count < 2 {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(seen == ["Hel", "lo"])
    #expect(finished)
    #expect(runner.isRunning == false)
}

/// A stream that is replaced cannot paint into the next question.
@MainActor
@Test func aSupersededStreamIsDropped() async {
    let runner = StandardAIRequest()
    var seen: [String] = []
    let first = runner.startStream(operation: { emit in
        emit("old")
        try await Task.sleep(nanoseconds: 50_000_000)
        emit("older")
        return "old"
    }, receive: { _ in
    }, delta: { seen.append($0) }, failure: { _ in
    })
    // Replace it before the second piece is emitted.
    runner.cancel()
    let second = runner.startStream(operation: { emit in
        emit("new")
        return "new"
    }, receive: { _ in
    }, delta: { seen.append($0) }, failure: { _ in
        Issue.record("the second stream failed")
    })
    await second.value
    await first.value
    for _ in 0..<50 where !seen.contains("new") {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(seen.contains("new"), "the second stream never reported")
    #expect(seen.contains("older") == false, "a cancelled stream painted after it was replaced")
}
