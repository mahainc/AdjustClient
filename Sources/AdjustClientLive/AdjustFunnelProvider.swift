import AdjustClient
import Dependencies
import Foundation
import FunnelClient
import LogClient

/// Serves FunnelClient's three marketing-side ports from one `AdjustClient`.
///
/// One object for three ports because they share one SDK instance, one init gate
/// and one revenue event token — three objects would each have to re-derive the
/// same configuration and race each other to initialise the SDK.
///
/// Everything FunnelClient-specific lives here, not in `AdjustClient`: which funnel
/// event names are ad revenue, which purchase kinds may be booked as subscriptions,
/// and which parameters travel with a purchase.
public final class AdjustFunnelProvider: FunnelClient.Attribution.Providing,
    FunnelClient.MarketingEvent.Providing,
    FunnelClient.IAPRevenue.Providing
{
    public struct Settings: Sendable {
        public let environment: AdjustClient.Environment
        /// Adjust event token every revenue event is reported under. Empty → revenue
        /// that is not an ad impression is dropped, because Adjust rejects a funnel
        /// event name used as an event token.
        public let revenueEventToken: String

        public init(
            environment: AdjustClient.Environment = .production,
            revenueEventToken: String = ""
        ) {
            self.environment = environment
            self.revenueEventToken = revenueEventToken
        }
    }

    private let adjustClient: AdjustClient
    private let settings: Settings

    public init(
        adjustClient: AdjustClient,
        settings: Settings = Settings()
    ) {
        self.adjustClient = adjustClient
        self.settings = settings
    }

    // MARK: - Attribution.Providing

    public func configure(token: String) {
        @Dependency(\.logClient) var log
        if token.isEmpty {
            log.funnel.attribution.notice(
                "Adjust configure SKIPPED empty token — SDK stays uninitialized, queued calls drained env=\(settings.environment)"
            )
        } else {
            log.funnel.attribution.info("Adjust configure env=\(settings.environment)")
        }
        // Ad revenue is reported once, as ADJAdRevenue: the mirror event stays off so
        // Adjust does not count the same impression twice.
        let config = AdjustClient.Config(
            appToken: token,
            environment: settings.environment,
            logLevel: Self.logLevel
        )
        Task { [adjustClient] in await adjustClient.initialize(config) }
    }

    public func attributionStream() -> AsyncStream<FunnelClient.Attribution.Install> {
        let (stream, continuation) = AsyncStream<FunnelClient.Attribution.Install>.makeStream()
        let task = Task { [adjustClient] in
            @Dependency(\.logClient) var log
            for await attribution in adjustClient.attributionStream() {
                let install = Self.install(from: attribution)
                log.funnel.attribution.info(
                    "Adjust attribution changed network=\(install.network ?? "nil") campaign=\(install.campaign ?? "nil") tracker=\(install.trackerName ?? "nil")"
                )
                continuation.yield(install)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: - MarketingEvent.Providing

    public func trackEvent(
        _ name: String,
        params: [String: String],
        revenue: FunnelClient.MarketingEvent.Revenue?
    ) {
        @Dependency(\.logClient) var log
        guard !name.isEmpty else {
            log.funnel.attribution.error("Adjust trackEvent SKIPPED empty name")
            return
        }
        // Adjust accepts its own event tokens, never a funnel event name, so an event
        // with no revenue to report has nowhere to go.
        guard let revenue else {
            log.funnel.attribution.debug(
                "Adjust trackEvent DROPPED name=\(name) — non-revenue event"
            )
            return
        }
        if AdImpressionEvent.matches(name) {
            trackAdRevenue(name: name, params: params, revenue: revenue)
        } else if !settings.revenueEventToken.isEmpty {
            trackRevenueEvent(name: name, params: params, revenue: revenue)
        } else {
            log.funnel.attribution.notice(
                "Adjust revenue DROPPED name=\(name) — no revenueEventToken configured amount=\(revenue.amount) \(revenue.currency)"
            )
        }
    }

    // MARK: - IAPRevenue.Providing

    public func trackPurchase(_ event: FunnelClient.IAPRevenue.Event) {
        switch event.kind {
            // Only a subscription may go out as ADJAppStoreSubscription; a one-off
            // purchase reported that way would be counted as recurring revenue.
            case .autoRenewable, .nonRenewing:
                trackSubscription(event)
            case .consumable, .nonConsumable, .unknown:
                trackPurchaseEvent(event)
        }
    }

    // MARK: - Marketing revenue routing

    private func trackAdRevenue(
        name: String,
        params: [String: String],
        revenue: FunnelClient.MarketingEvent.Revenue
    ) {
        @Dependency(\.logClient) var log
        log.funnel.attribution.info(
            "Adjust trackAdRevenue name=\(name) amount=\(revenue.amount) \(revenue.currency) network=\(Self.adRevenueNetwork)"
        )
        // The funnel reports the ad unit and placement inside `params`, so both stay
        // empty here and every param travels as a callback parameter.
        let adRevenue = AdjustClient.Revenue(
            amount: revenue.amount,
            currency: revenue.currency,
            adUnit: "",
            network: Self.adRevenueNetwork,
            source: Self.adRevenueSource,
            placement: "",
            callbackParameters: params
        )
        Task { [adjustClient] in await adjustClient.trackRevenue(adRevenue) }
    }

    private func trackRevenueEvent(
        name: String,
        params: [String: String],
        revenue: FunnelClient.MarketingEvent.Revenue
    ) {
        @Dependency(\.logClient) var log
        let token = settings.revenueEventToken
        log.funnel.attribution.info(
            "Adjust trackEvent revenue name=\(name) eventToken=\(token) amount=\(revenue.amount) \(revenue.currency)"
        )
        let event = AdjustClient.RevenueEvent(
            eventToken: token,
            amount: Decimal(revenue.amount),
            currency: revenue.currency,
            partnerParameters: params
        )
        Task { [adjustClient] in await adjustClient.trackRevenueEvent(event) }
    }

    // MARK: - Purchase routing

    private func trackSubscription(_ event: FunnelClient.IAPRevenue.Event) {
        @Dependency(\.logClient) var log
        let params = Self.purchaseParams(event)
        let subscription = AdjustClient.Subscription(
            price: event.amount,
            currency: event.currency,
            transactionId: event.transactionID,
            transactionDate: event.purchaseDate,
            // Adjust treats an empty sales region as a value, so drop it instead.
            salesRegion: event.metadata?.salesRegion.flatMap { $0.isEmpty ? nil : $0 },
            callbackParameters: params,
            partnerParameters: params
        )
        log.funnel.attribution.info(
            "Adjust trackAppStoreSubscription kind=\(event.kind.rawValue) product=\(event.productID) amount=\(event.amount) \(event.currency)"
        )
        Task { [adjustClient] in await adjustClient.trackSubscription(subscription) }
    }

    private func trackPurchaseEvent(_ event: FunnelClient.IAPRevenue.Event) {
        @Dependency(\.logClient) var log
        let token = settings.revenueEventToken
        guard !token.isEmpty else {
            log.funnel.attribution.notice(
                "Adjust IAP revenue DROPPED product=\(event.productID) kind=\(event.kind.rawValue) — no revenueEventToken configured amount=\(event.amount) \(event.currency)"
            )
            return
        }
        let purchase = AdjustClient.RevenueEvent(
            eventToken: token,
            amount: event.amount,
            currency: event.currency,
            productId: event.productID,
            transactionId: event.transactionID,
            partnerParameters: Self.purchaseParams(event)
        )
        log.funnel.attribution.info(
            "Adjust trackEvent IAP kind=\(event.kind.rawValue) product=\(event.productID) eventToken=\(token) amount=\(event.amount) \(event.currency)"
        )
        Task { [adjustClient] in await adjustClient.trackRevenueEvent(purchase) }
    }

    // MARK: - Mapping

    private static let adRevenueSource = "admob_sdk"
    private static let adRevenueNetwork = "AdMob"

    private static var logLevel: AdjustClient.LogLevel {
        #if DEBUG
        .verbose
        #else
        .info
        #endif
    }

    /// Funnel event names the ad SDK reports as impressions. They must be booked as
    /// ad revenue rather than IAP revenue. FunnelClient keeps the same two names
    /// internally, where this module cannot reach them.
    private enum AdImpressionEvent {
        static let standard = "ad_impression"
        static let native = "native_ad_impression"

        static func matches(_ name: String) -> Bool {
            name == standard || name == native
        }
    }

    private static func install(from attribution: AdjustClient.Attribution) -> FunnelClient.Attribution.Install {
        FunnelClient.Attribution.Install(
            network: attribution.network,
            campaign: attribution.campaign,
            adgroup: attribution.adgroup,
            creative: attribution.creative,
            trackerName: attribution.trackerName
        )
    }

    private static func purchaseParams(_ event: FunnelClient.IAPRevenue.Event) -> [String: String] {
        var params: [String: String] = [
            "product_id": event.productID,
            "product_type": event.kind.rawValue,
        ]
        if let originalTransactionID = event.originalTransactionID, !originalTransactionID.isEmpty {
            params["original_transaction_id"] = originalTransactionID
        }
        if let expirationDate = event.expirationDate {
            let formatter = ISO8601DateFormatter()
            params["expiration_date"] = formatter.string(from: expirationDate)
        }
        if let ownershipType = event.metadata?.ownershipType {
            params["ownership_type"] = ownershipType
        }
        if let environment = event.metadata?.environment {
            params["environment"] = environment
        }
        if let period = event.metadata?.period {
            params["period_unit"] = period.unit
            params["period_value"] = String(period.value)
        }
        if let offer = event.metadata?.offer {
            params["offer_type"] = offer.kind
            params["offer_payment_mode"] = offer.paymentMode
        }
        return params
    }
}
