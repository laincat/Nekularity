import Observation

/// Owns the standard AI screen's current catalog or conversation request.
///
/// The operation runs in the task that is cancelled, so cancellation reaches
/// Core/URLSession. A cancelled or superseded operation cannot publish a late
/// answer, error, or busy-state change into the next request.
@MainActor
@Observable
public final class StandardAIRequest {
    public private(set) var isRunning = false

    @ObservationIgnored private var task: Task<Void, Never>?
    private let generation = SearchGeneration()

    public init() {}

    @discardableResult
    public func start<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value,
        receive: @escaping @MainActor (Value) -> Void,
        failure: @escaping @MainActor (any Error) -> Void
    ) -> Task<Void, Never> {
        let token = generation.begin()
        task?.cancel()
        isRunning = true
        let current = Task { @MainActor in
            defer {
                generation.commit(token) {
                    self.task = nil
                    self.isRunning = false
                }
            }
            do {
                let value = try await operation()
                guard !Task.isCancelled else { return }
                generation.commit(token) { receive(value) }
            } catch {
                guard !Task.isCancelled else { return }
                generation.commit(token) { failure(error) }
            }
        }
        task = current
        return current
    }

    public func cancel() {
        _ = generation.begin()
        let current = task
        task = nil
        isRunning = false
        current?.cancel()
    }
}
