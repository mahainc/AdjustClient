import DependenciesMacros
import Foundation

@DependencyClient
public struct AdjustClient: Sendable {
    public var initialize:     @Sendable (_ config: Config) async -> Void
    public var trackEvent:     @Sendable (_ token: String, _ params: [String: String]) async -> Void
    public var trackRevenue:   @Sendable (_ revenue: Revenue) async -> Void
    public var setDeviceToken: @Sendable (_ token: Data) async -> Void

    /// Forward an inbound Adjust campaign URL (received via
    /// `UIScene.openURLContexts` while the app is already installed) so Adjust
    /// can register the click and re-attribute. `referrer` is the optional
    /// originating URL when the OS exposes one (organic search, etc.).
    public var processDeeplink: @Sendable (_ url: URL, _ referrer: URL?) async -> Void

    /// Same as `processDeeplink`, but also asks Adjust's backend to unshorten
    /// any short link and return the resolved final URL for app routing.
    /// Returns `nil` if the SDK can't resolve.
    public var resolveDeeplink: @Sendable (_ url: URL, _ referrer: URL?) async -> URL?

    /// Track an auto-renewable IAP subscription. Use for renewals AND first
    /// purchase — Adjust dedups by `transactionId` server-side.
    public var trackSubscription: @Sendable (_ subscription: Subscription) async -> Void

    /// Receipt-validate an IAP via Adjust's anti-fraud backend and, on success,
    /// fire the supplied event token (with optional revenue/currency).
    /// Always returns a `PurchaseVerification` — `.notVerified` means the SDK
    /// or network failed before the backend was reached.
    public var verifyAndTrackPurchase: @Sendable (
        _ token: String,
        _ purchase: Purchase,
        _ revenue: Revenue?
    ) async -> PurchaseVerification = { _, _, _ in
        PurchaseVerification(status: .notVerified, code: -1, message: nil)
    }

    /// Master kill-switch. `false` pauses ALL tracking (sessions, events,
    /// revenue). State persists across launches. Use for user-facing privacy
    /// toggles. For irreversible GDPR opt-out use `gdprForgetMe` instead.
    public var setEnabled: @Sendable (_ enabled: Bool) async -> Void

    /// Current value of the master kill-switch.
    public var isEnabled: @Sendable () async -> Bool = { true }

    /// One-way GDPR opt-out. Stops tracking, deletes user's data on the Adjust
    /// backend, and the user cannot be re-tracked on this device install.
    /// Do not call without explicit user consent.
    public var gdprForgetMe: @Sendable () async -> Void

    /// Apply CCPA-class third-party sharing rules globally or per partner.
    public var setThirdPartySharing: @Sendable (_ sharing: ThirdPartySharing) async -> Void

    /// GDPR measurement consent flag. `true` = user opted in to measurement.
    public var setMeasurementConsent: @Sendable (_ enabled: Bool) async -> Void

    /// Attribution emitted by Adjust after install. Fires once the SDK
    /// resolves campaign / adgroup / creative / network on the server. The
    /// stream is multicast so a subscriber can fan the result to
    /// `AnalyticClient.setUserProperty(...)` without coupling this client to
    /// analytics. Must be called **after** `initialize(_:)`.
    public var attributionStream: @Sendable () -> AsyncStream<Attribution> = { .finished }
    /// Deferred deep links delivered via Adjust's
    /// `adjustDeferredDeeplinkReceived(_:)`. Fires when the user clicked an
    /// Adjust deep-link ad before installing the app — Adjust posts the URL
    /// back on first launch. The app target is expected to return `false`
    /// to Adjust's "auto-open" path so subscribers handle the URL themselves
    /// (e.g. deep-link into SubscriptionFeature). Regular (warm) deep links
    /// should continue to flow through `UIScene.openURLContexts`.
    public var deeplinkStream: @Sendable () -> AsyncStream<URL> = { .finished }
}
