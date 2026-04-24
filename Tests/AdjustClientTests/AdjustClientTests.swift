import Foundation
import Testing
@testable import AdjustClient

@Suite("AdjustClient")
struct AdjustClientTests {

    @Test("AdjustConfig captures revenue event token")
    func configStoresToken() {
        let config = AdjustConfig(
            appToken: "abc",
            environment: .sandbox,
            logLevel: .verbose,
            revenueEventToken: "rev_token"
        )
        #expect(config.appToken == "abc")
        #expect(config.environment == .sandbox)
        #expect(config.logLevel == .verbose)
        #expect(config.revenueEventToken == "rev_token")
    }

    @Test("AdjustRevenue has sensible defaults")
    func revenueDefaults() {
        let rev = AdjustRevenue(amount: 0.01, currency: "USD", adUnit: "interstitial")
        #expect(rev.network == "AdMob")
        #expect(rev.source == "admob_sdk")
        #expect(rev.placement == "default")
        #expect(rev.impressions == 1)
    }

    @Test("noop mock absorbs all calls including empty appToken")
    func noopDoesntCrashOnEmptyToken() async {
        let client = AdjustClient.noop
        await client.initialize(AdjustConfig(appToken: "", environment: .sandbox))
        await client.trackEvent("t", [:])
        await client.trackRevenue(AdjustRevenue(amount: 0.01, currency: "USD", adUnit: "banner"))
        await client.setDeviceToken(Data())
    }

    @Test("custom client forwards revenue payload")
    func customForwardsRevenue() async {
        actor Spy { var last: AdjustRevenue?; func record(_ r: AdjustRevenue) { last = r } }
        let spy = Spy()
        let client = AdjustClient(
            initialize: { _ in },
            trackEvent: { _, _ in },
            trackRevenue: { await spy.record($0) },
            setDeviceToken: { _ in }
        )
        let rev = AdjustRevenue(amount: 0.005, currency: "USD", adUnit: "rewarded")
        await client.trackRevenue(rev)
        let captured = await spy.last
        #expect(captured?.amount == 0.005)
        #expect(captured?.adUnit == "rewarded")
    }
}
