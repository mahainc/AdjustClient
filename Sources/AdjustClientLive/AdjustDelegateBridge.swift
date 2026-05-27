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
