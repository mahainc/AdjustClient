//
//  AdjustDelegateBridge.swift
//  AdjustClient
//
//  Bridges Adjust's `AdjustDelegate` into the two `AsyncStream`s exposed by
//  `AdjustClient.attributionStream()` and `AdjustClient.deeplinkStream()`.
//  A single MainActor-isolated `shared` instance is wired onto `ADJConfig.delegate`
//  inside `AdjustState.configure(with:)`; subscribers register UUID-keyed
//  continuations via the two multicast actors.
//
//  The pattern mirrors `AdRevenueActor` — lean continuation bag with
//  `onTermination` cleanup — but we need two of them (attribution + deeplink)
//  so the bridge holds both.
//

import AdjustClient
@preconcurrency import AdjustSdk
import Foundation

/// One multicast bag per stream type. Copy of `AdRevenueActor` with a
/// different element type; kept per-file so each client owns its own.
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

/// Obj-C-visible delegate required by `ADJConfig.delegate`. Held as a singleton
/// because `AdjustDelegate` isn't retained by the SDK — if we set a local
/// delegate it gets deallocated and the SDK silently drops callbacks. Fans
/// events into process-wide actors so multiple subscribers can observe them.
///
/// `@unchecked Sendable` because the stored actors are already concurrency-
/// safe and all other state is `let`; the Adjust SDK invokes delegate methods
/// off arbitrary threads, so the class must cross isolation boundaries.
final class AdjustDelegateBridge: NSObject, AdjustDelegate, @unchecked Sendable {
    static let shared = AdjustDelegateBridge()

    let attributionActor = AdjustAttributionActor()
    let deeplinkActor = AdjustDeeplinkActor()

    private override init() {
        super.init()
    }

    func adjustAttributionChanged(_ attribution: ADJAttribution?) {
        let mapped = AdjustClient.Attribution(
            trackerToken: attribution?.trackerToken,
            trackerName:  attribution?.trackerName,
            network:      attribution?.network,
            campaign:     attribution?.campaign,
            adgroup:      attribution?.adgroup,
            creative:     attribution?.creative,
            clickLabel:   attribution?.clickLabel,
            costType:     attribution?.costType,
            costAmount:   attribution?.costAmount?.doubleValue,
            costCurrency: attribution?.costCurrency
        )
        Task { [attributionActor] in await attributionActor.publish(mapped) }
    }

    func adjustDeferredDeeplinkReceived(_ deeplink: URL?) -> Bool {
        if let deeplink {
            Task { [deeplinkActor] in await deeplinkActor.publish(deeplink) }
        }
        // `false` — subscribers handle the URL; prevents Adjust from auto-
        // opening it, which would bypass the app's own routing.
        return false
    }
}
