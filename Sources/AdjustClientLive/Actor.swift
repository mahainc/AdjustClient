import AdjustClient
import Foundation

actor AdjustAttributionActor {
    private var continuations: [UUID: AsyncStream<AdjustClient.Attribution>.Continuation] = [:]

    init() {}

    func publish(_ attribution: AdjustClient.Attribution) {
        for continuation in continuations.values {
            continuation.yield(attribution)
        }
    }

    nonisolated func stream() -> AsyncStream<AdjustClient.Attribution> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(
        id: UUID,
        continuation: AsyncStream<AdjustClient.Attribution>.Continuation
    ) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

actor AdjustDeeplinkActor {
    private var continuations: [UUID: AsyncStream<URL>.Continuation] = [:]

    init() {}

    func publish(_ url: URL) {
        for continuation in continuations.values {
            continuation.yield(url)
        }
    }

    nonisolated func stream() -> AsyncStream<URL> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(
        id: UUID,
        continuation: AsyncStream<URL>.Continuation
    ) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
