import Foundation
import Testing
@testable import NekularityKit

@MainActor
@Suite("Standard AI request lifetime")
struct StandardAIRequestTests {
    private actor Signal {
        private var signalled = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if signalled { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func signal() {
            signalled = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func mark() { lock.lock(); cancelled = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    @Test func aCompletedRequestPublishesOnceAndBecomesIdle() async {
        let request = StandardAIRequest()
        var values: [Int] = []
        var errors: [String] = []
        let job = request.start(operation: { 42 }, receive: { values.append($0) },
                                failure: { errors.append($0.localizedDescription) })
        #expect(request.isRunning)
        await job.value
        #expect(values == [42])
        #expect(errors.isEmpty)
        #expect(!request.isRunning)
    }

    @Test func stopCancelsTheActualOperationAndDiscardsItsAnswer() async {
        let request = StandardAIRequest()
        let started = Signal(), release = Signal()
        let cancellation = CancellationFlag()
        var values: [String] = []
        var errors: [String] = []
        let job = request.start(operation: {
            await withTaskCancellationHandler {
                await started.signal()
                // Deliberately return even after cancellation, like an adapter
                // whose completion was already queued when it was stopped.
                await release.wait()
                return "late"
            } onCancel: {
                cancellation.mark()
            }
        }, receive: { values.append($0) }, failure: { errors.append($0.localizedDescription) })
        await started.wait()
        request.cancel()
        #expect(!request.isRunning)
        await release.signal()
        await job.value
        #expect(cancellation.value, "the request must cancel the operation, not only a detached task's waiter")
        #expect(values.isEmpty)
        #expect(errors.isEmpty)
    }

    private func oldCompletionCannotFinishTheReplacement(throwLate: Bool) async {
        let request = StandardAIRequest()
        let oldStarted = Signal(), oldRelease = Signal()
        let newStarted = Signal(), newRelease = Signal()
        var values: [String] = []
        var errors: [String] = []
        let old = request.start(operation: {
            await oldStarted.signal()
            await oldRelease.wait()
            if throwLate { throw StandardAIError("late error") }
            return "old"
        }, receive: { values.append($0) }, failure: { errors.append($0.localizedDescription) })
        await oldStarted.wait()
        let current = request.start(operation: {
            await newStarted.signal()
            await newRelease.wait()
            return "new"
        }, receive: { values.append($0) }, failure: { errors.append($0.localizedDescription) })
        await newStarted.wait()
        await oldRelease.signal()
        await old.value
        #expect(request.isRunning, "old completion must not clear the replacement's busy state")
        #expect(values.isEmpty)
        #expect(errors.isEmpty)
        await newRelease.signal()
        await current.value
        #expect(values == ["new"])
        #expect(errors.isEmpty)
        #expect(!request.isRunning)
    }

    @Test func aLateAnswerCannotFinishTheReplacement() async {
        await oldCompletionCannotFinishTheReplacement(throwLate: false)
    }

    @Test func aLateErrorCannotFinishTheReplacement() async {
        await oldCompletionCannotFinishTheReplacement(throwLate: true)
    }

    @Test func aCurrentErrorIsPublishedAndBecomesIdle() async {
        let request = StandardAIRequest()
        var values: [String] = []
        var errors: [String] = []
        let job = request.start(operation: { () async throws -> String in
            throw StandardAIError("fixture denied")
        }, receive: { values.append($0) }, failure: { errors.append($0.localizedDescription) })
        await job.value
        #expect(values.isEmpty)
        #expect(errors == ["fixture denied"])
        #expect(!request.isRunning)
    }
}
