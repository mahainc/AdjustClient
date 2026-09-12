import AdjustClient
@preconcurrency import AdjustSdk
import Dependencies
import Foundation

extension AdjustClient: DependencyKey {
    public static var liveValue: Self {
        let state = AdjustState()
        return .init(
            initialize: { config in
                await state.configure(with: config)
            },
            trackEvent: { token, params in
                guard !token.isEmpty else { return }
                await state.perform { _ in
                    let event = ADJEvent(eventToken: token)
                    for (key, value) in params {
                        event?.addPartnerParameter(key, value: value)
                    }
                    Adjust.trackEvent(event)
                }
            },
            trackRevenue: { revenue in
                await state.perform { config in
                    let adRevenue = ADJAdRevenue(source: revenue.source)
                    adRevenue?.setRevenue(revenue.amount, currency: revenue.currency)
                    adRevenue?.setAdImpressionsCount(Int32(revenue.impressions))
                    adRevenue?.setAdRevenueNetwork(revenue.network)
                    if !revenue.adUnit.isEmpty {
                        adRevenue?.setAdRevenueUnit(revenue.adUnit)
                    }
                    if !revenue.placement.isEmpty {
                        adRevenue?.setAdRevenuePlacement(revenue.placement)
                    }
                    for (key, value) in revenue.callbackParameters {
                        adRevenue?.addCallbackParameter(key, value: value)
                    }
                    for (key, value) in revenue.partnerParameters {
                        adRevenue?.addPartnerParameter(key, value: value)
                    }
                    if let adRevenue {
                        Adjust.trackAdRevenue(adRevenue)
                    }

                    guard config?.mirrorsAdRevenueAsEvent == true,
                        let token = config?.revenueEventToken,
                        !token.isEmpty
                    else { return }
                    let event = ADJEvent(eventToken: token)
                    event?.setRevenue(revenue.amount, currency: revenue.currency)
                    Adjust.trackEvent(event)
                }
            },
            setDeviceToken: { data in
                await state.perform { _ in
                    Adjust.setPushToken(data)
                }
            },
            processDeeplink: { url, referrer in
                await state.perform { _ in
                    guard let deeplink = ADJDeeplink(deeplink: url) else { return }
                    if let referrer { deeplink.setReferrer(referrer) }
                    Adjust.processDeeplink(deeplink)
                }
            },
            resolveDeeplink: { url, referrer in
                await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    Task {
                        await state.perform { config in
                            guard config != nil else {
                                continuation.resume(returning: nil)
                                return
                            }
                            guard let deeplink = ADJDeeplink(deeplink: url) else {
                                continuation.resume(returning: nil)
                                return
                            }
                            if let referrer { deeplink.setReferrer(referrer) }
                            Adjust.processAndResolve(deeplink) { resolved in
                                continuation.resume(returning: resolved.flatMap(URL.init(string:)))
                            }
                        }
                    }
                }
            },
            trackSubscription: { subscription in
                await state.perform { _ in
                    let price = NSDecimalNumber(decimal: subscription.price)
                    guard
                        let adjSub = ADJAppStoreSubscription(
                            price: price,
                            currency: subscription.currency,
                            transactionId: subscription.transactionId
                        )
                    else { return }
                    if let date = subscription.transactionDate {
                        adjSub.setTransactionDate(date)
                    }
                    if let region = subscription.salesRegion {
                        adjSub.setSalesRegion(region)
                    }
                    for (key, value) in subscription.callbackParameters {
                        adjSub.addCallbackParameter(key, value: value)
                    }
                    for (key, value) in subscription.partnerParameters {
                        adjSub.addPartnerParameter(key, value: value)
                    }
                    Adjust.trackAppStoreSubscription(adjSub)
                }
            },
            trackRevenueEvent: { event in
                guard !event.eventToken.isEmpty else { return }
                await state.perform { config in
                    guard config != nil, let adjEvent = ADJEvent(eventToken: event.eventToken) else { return }
                    adjEvent.setRevenue(
                        NSDecimalNumber(decimal: event.amount).doubleValue,
                        currency: event.currency
                    )
                    if let productId = event.productId {
                        adjEvent.setProductId(productId)
                    }
                    if let transactionId = event.transactionId {
                        adjEvent.setTransactionId(transactionId)
                    }
                    for (key, value) in event.callbackParameters {
                        adjEvent.addCallbackParameter(key, value: value)
                    }
                    for (key, value) in event.partnerParameters {
                        adjEvent.addPartnerParameter(key, value: value)
                    }
                    Adjust.trackEvent(adjEvent)
                }
            },
            verifyAndTrackPurchase: { token, purchase, revenue in
                await withCheckedContinuation { (continuation: CheckedContinuation<PurchaseVerification, Never>) in
                    Task {
                        await state.perform { config in
                            guard config != nil else {
                                continuation.resume(
                                    returning: PurchaseVerification(
                                        status: .notVerified,
                                        code: -1,
                                        message: "Adjust SDK not initialized"
                                    )
                                )
                                return
                            }
                            guard !token.isEmpty, let event = ADJEvent(eventToken: token) else {
                                continuation.resume(
                                    returning: PurchaseVerification(
                                        status: .notVerified,
                                        code: -1,
                                        message: "Invalid event token"
                                    )
                                )
                                return
                            }
                            event.setTransactionId(purchase.transactionId)
                            event.setProductId(purchase.productId)
                            if let revenue {
                                event.setRevenue(revenue.amount, currency: revenue.currency)
                            }
                            Adjust.verifyAndTrackAppStorePurchase(event) { result in
                                continuation.resume(
                                    returning: PurchaseVerification(
                                        status: PurchaseVerification.Status(rawAdjustValue: result.verificationStatus),
                                        code: Int(result.code),
                                        message: result.message
                                    )
                                )
                            }
                        }
                    }
                }
            },
            setEnabled: { enabled in
                await state.perform { _ in
                    if enabled {
                        Adjust.enable()
                    } else {
                        Adjust.disable()
                    }
                }
            },
            isEnabled: {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    Task {
                        await state.perform { config in
                            guard config != nil else {
                                continuation.resume(returning: false)
                                return
                            }
                            Adjust.isEnabled { isEnabled in
                                continuation.resume(returning: isEnabled)
                            }
                        }
                    }
                }
            },
            gdprForgetMe: {
                await state.perform { _ in
                    Adjust.gdprForgetMe()
                }
            },
            setThirdPartySharing: { sharing in
                await state.perform { _ in
                    let isEnabled: NSNumber? = sharing.isEnabled.map { NSNumber(value: $0) }
                    guard let adjSharing = ADJThirdPartySharing(isEnabled: isEnabled) else { return }
                    for (partner, options) in sharing.granularOptions {
                        for (key, value) in options {
                            adjSharing.addGranularOption(partner, key: key, value: value)
                        }
                    }
                    for (partner, settings) in sharing.partnerSharingSettings {
                        for (key, value) in settings {
                            adjSharing.addPartnerSharingSetting(partner, key: key, value: value)
                        }
                    }
                    Adjust.trackThirdPartySharing(adjSharing)
                }
            },
            setMeasurementConsent: { enabled in
                await state.perform { _ in
                    Adjust.trackMeasurementConsent(enabled)
                }
            },
            attributionStream: {
                AdjustDelegateBridge.shared.attributionActor.stream()
            },
            deeplinkStream: {
                AdjustDelegateBridge.shared.deeplinkActor.stream()
            }
        )
    }
}

/// Gates every SDK call behind `Adjust.initSdk`. Calls made before
/// `configure(with:)` completes are enqueued and fired in order once the
/// SDK is initialised — otherwise Adjust logs
/// `[Adjust]e: Please initialize Adjust by calling initSdk: before` and
/// silently drops the call.
///
/// Thunks receive the resolved `Config?` at execution time so
/// `trackRevenue` can read the current `revenueEventToken` even if the
/// call was queued before `configure` ran. A `nil` config signals
/// "the SDK is not running" — init was abandoned (e.g. empty appToken) —
/// so completion-bearing thunks resume their continuations with a
/// sentinel rather than hanging forever.
///
/// `configure(with:)` runs at most once: Adjust's own SDK does not expect a
/// second `initSdk`, and once init has been attempted nothing is queued any
/// more, because nothing would ever drain it.
private actor AdjustState {
    private var config: AdjustClient.Config?
    private var isInitialized = false
    private var didAttemptInit = false
    private var pending: [@Sendable (AdjustClient.Config?) -> Void] = []

    func configure(with config: AdjustClient.Config) {
        guard !didAttemptInit else { return }
        didAttemptInit = true
        self.config = config

        guard !config.appToken.isEmpty else {
            #if DEBUG
            print(
                "[AdjustClient] ⚠️ appToken is empty — skipping Adjust.initSdk (\(pending.count) queued call(s) dropped)"
            )
            #endif
            // Drain with nil so completion-bearing thunks can resume their
            // continuations rather than leak. Fire-and-forget thunks ignore the
            // config and reach an uninitialised SDK, which logs and drops them.
            let abandoned = pending
            pending.removeAll()
            for work in abandoned { work(nil) }
            return
        }

        let env: String
        switch config.environment {
            case .sandbox: env = ADJEnvironmentSandbox
            case .production: env = ADJEnvironmentProduction
        }

        let adjustConfig = ADJConfig(appToken: config.appToken, environment: env)
        adjustConfig?.logLevel = config.logLevel.adjustValue
        // Install the shared delegate bridge so attribution + deferred-
        // deep-link callbacks fan into our AsyncStreams. Must be set before
        // `Adjust.initSdk` — the SDK retains the delegate weakly, so a
        // singleton keeps it alive for the process lifetime.
        adjustConfig?.delegate = AdjustDelegateBridge.shared
        Adjust.initSdk(adjustConfig)
        isInitialized = true

        // Drain in insertion order. Each thunk receives the resolved config.
        let queued = pending
        pending.removeAll()
        for work in queued {
            work(config)
        }
    }

    /// Runs `work` immediately when the SDK is initialised, otherwise
    /// enqueues it. The closure is fired with the current `config` so
    /// callers that depend on it (e.g. `trackRevenue` reading
    /// `revenueEventToken`) see the post-init value. A `nil` config
    /// argument means the SDK is not running — completion-bearing callers
    /// should resume their continuation with a sentinel value.
    ///
    /// Work only queues while init is still ahead of us. Once init has been
    /// attempted and abandoned the queue is never drained again, so queueing
    /// there would hang every caller awaiting a continuation forever.
    func perform(_ work: @escaping @Sendable (AdjustClient.Config?) -> Void) {
        if isInitialized {
            work(config)
        } else if didAttemptInit {
            work(nil)
        } else {
            pending.append(work)
        }
    }
}

extension AdjustClient.LogLevel {
    fileprivate var adjustValue: ADJLogLevel {
        switch self {
            case .verbose: return .verbose
            case .debug: return .debug
            case .info: return .info
            case .warn: return .warn
            case .error: return .error
            case .suppress: return .suppress
        }
    }
}
