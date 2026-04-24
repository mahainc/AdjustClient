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
                let event = ADJEvent(eventToken: token)
                for (key, value) in params {
                    event?.addPartnerParameter(key, value: value)
                }
                Adjust.trackEvent(event)
            },
            trackRevenue: { revenue in
                let adRevenue = ADJAdRevenue(source: revenue.source)
                adRevenue?.setRevenue(revenue.amount, currency: revenue.currency)
                adRevenue?.setAdImpressionsCount(Int32(revenue.impressions))
                adRevenue?.setAdRevenueNetwork(revenue.network)
                adRevenue?.setAdRevenueUnit(revenue.adUnit)
                adRevenue?.setAdRevenuePlacement(revenue.placement)
                if let adRevenue {
                    Adjust.trackAdRevenue(adRevenue)
                }

                if let token = await state.revenueEventToken(), !token.isEmpty {
                    let event = ADJEvent(eventToken: token)
                    event?.setRevenue(revenue.amount, currency: revenue.currency)
                    Adjust.trackEvent(event)
                }
            },
            setDeviceToken: { data in
                Adjust.setPushToken(data)
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

/// Holds the one-shot config passed to `initialize(_:)` so `trackRevenue` can read
/// the optional `revenueEventToken` later. Avoids a shared mutable singleton.
private actor AdjustState {
    private var config: AdjustClient.Config?

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
    }

    func revenueEventToken() -> String? {
        return config?.revenueEventToken
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
