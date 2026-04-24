import Dependencies
import AdjustClient
@preconcurrency import AdjustSdk
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
                    adRevenue?.setAdRevenueUnit(revenue.adUnit)
                    adRevenue?.setAdRevenuePlacement(revenue.placement)
                    if let adRevenue {
                        Adjust.trackAdRevenue(adRevenue)
                    }

                    if let token = config?.revenueEventToken, !token.isEmpty {
                        let event = ADJEvent(eventToken: token)
                        event?.setRevenue(revenue.amount, currency: revenue.currency)
                        Adjust.trackEvent(event)
                    }
                }
            },
            setDeviceToken: { data in
                await state.perform { _ in
                    Adjust.setPushToken(data)
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
/// call was queued before `configure` ran.
private actor AdjustState {
    private var config: AdjustClient.Config?
    private var isInitialized = false
    private var pending: [@Sendable (AdjustClient.Config?) -> Void] = []

    func configure(with config: AdjustClient.Config) {
        self.config = config

        guard !config.appToken.isEmpty else {
            #if DEBUG
            print("[AdjustClient] ⚠️ appToken is empty — skipping Adjust.initSdk")
            #endif
            return
        }

        let env: String
        switch config.environment {
        case .sandbox:    env = ADJEnvironmentSandbox
        case .production: env = ADJEnvironmentProduction
        }

        let adjustConfig = ADJConfig(appToken: config.appToken, environment: env)
        adjustConfig?.logLevel = config.logLevel.adjustValue
        // Install the shared delegate bridge so attribution + deferred-
        // deep-link callbacks fan into our AsyncStreams. Must be set before
        // `Adjust.initSdk` — the SDK captures the delegate reference during
        // init and ignores later changes on the same process.
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
    /// `revenueEventToken`) see the post-init value.
    func perform(_ work: @escaping @Sendable (AdjustClient.Config?) -> Void) {
        if isInitialized {
            work(config)
        } else {
            pending.append(work)
        }
    }
}

private extension AdjustClient.LogLevel {
    var adjustValue: ADJLogLevel {
        switch self {
        case .verbose:  return .verbose
        case .debug:    return .debug
        case .info:     return .info
        case .warn:     return .warn
        case .error:    return .error
        case .suppress: return .suppress
        }
    }
}
