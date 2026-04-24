import DependenciesMacros
import Foundation

@DependencyClient
public struct AdjustClient: Sendable {
    public var initialize:     @Sendable (_ config: Config) async -> Void
    public var trackEvent:     @Sendable (_ token: String, _ params: [String: String]) async -> Void
    public var trackRevenue:   @Sendable (_ revenue: Revenue) async -> Void
    public var setDeviceToken: @Sendable (_ token: Data) async -> Void
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
