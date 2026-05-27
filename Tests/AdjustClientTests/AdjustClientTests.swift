import Foundation
import Testing
@testable import AdjustClient

@Suite("AdjustClient")
struct AdjustClientTests {

    @Test("Config captures revenue event token")
    func configStoresToken() {
        let config = AdjustClient.Config(
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

    @Test("Revenue has sensible defaults")
    func revenueDefaults() {
        let rev = AdjustClient.Revenue(amount: 0.01, currency: "USD", adUnit: "interstitial")
        #expect(rev.network == "AdMob")
        #expect(rev.source == "admob_sdk")
        #expect(rev.placement == "default")
        #expect(rev.impressions == 1)
    }

    @Test("Subscription preserves required + optional fields")
    func subscriptionFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sub = AdjustClient.Subscription(
            price: Decimal(string: "9.99")!,
            currency: "USD",
            transactionId: "tx-123",
            transactionDate: date,
            salesRegion: "US",
            callbackParameters: ["k": "v"],
            partnerParameters: ["p": "q"]
        )
        #expect(sub.price == Decimal(string: "9.99"))
        #expect(sub.currency == "USD")
        #expect(sub.transactionId == "tx-123")
        #expect(sub.transactionDate == date)
        #expect(sub.salesRegion == "US")
        #expect(sub.callbackParameters == ["k": "v"])
        #expect(sub.partnerParameters == ["p": "q"])
    }

    @Test("Subscription defaults — no date, region, or params")
    func subscriptionDefaults() {
        let sub = AdjustClient.Subscription(price: 1, currency: "USD", transactionId: "tx")
        #expect(sub.transactionDate == nil)
        #expect(sub.salesRegion == nil)
        #expect(sub.callbackParameters.isEmpty)
        #expect(sub.partnerParameters.isEmpty)
    }

    @Test("Purchase stores productId + transactionId")
    func purchaseFields() {
        let p = AdjustClient.Purchase(productId: "premium.monthly", transactionId: "tx-9")
        #expect(p.productId == "premium.monthly")
        #expect(p.transactionId == "tx-9")
    }

    @Test("PurchaseVerification.Status maps Adjust raw values")
    func verificationStatusMapping() {
        #expect(AdjustClient.PurchaseVerification.Status(rawAdjustValue: "success") == .success)
        #expect(AdjustClient.PurchaseVerification.Status(rawAdjustValue: "failure") == .failure)
        #expect(AdjustClient.PurchaseVerification.Status(rawAdjustValue: "not_verified") == .notVerified)
        #expect(AdjustClient.PurchaseVerification.Status(rawAdjustValue: "anything_else") == .unknown)
        #expect(AdjustClient.PurchaseVerification.Status(rawAdjustValue: nil) == .unknown)
    }

    @Test("ThirdPartySharing defaults — nil isEnabled, empty dicts")
    func thirdPartySharingDefaults() {
        let sharing = AdjustClient.ThirdPartySharing()
        #expect(sharing.isEnabled == nil)
        #expect(sharing.granularOptions.isEmpty)
        #expect(sharing.partnerSharingSettings.isEmpty)
    }

    @Test("ThirdPartySharing carries per-partner settings")
    func thirdPartySharingFields() {
        let sharing = AdjustClient.ThirdPartySharing(
            isEnabled: false,
            granularOptions: ["facebook": ["consent": "granted"]],
            partnerSharingSettings: ["snapchat": ["everything": false]]
        )
        #expect(sharing.isEnabled == false)
        #expect(sharing.granularOptions["facebook"]?["consent"] == "granted")
        #expect(sharing.partnerSharingSettings["snapchat"]?["everything"] == false)
    }

    @Test("noop absorbs every endpoint without crashing")
    func noopAbsorbsEverything() async {
        let client = AdjustClient.noop
        await client.initialize(AdjustClient.Config(appToken: "", environment: .sandbox))
        await client.trackEvent("t", [:])
        await client.trackRevenue(AdjustClient.Revenue(amount: 0.01, currency: "USD", adUnit: "banner"))
        await client.setDeviceToken(Data())
        await client.processDeeplink(URL(string: "adjust://x")!, nil)
        let resolved = await client.resolveDeeplink(URL(string: "adjust://x")!, nil)
        #expect(resolved == nil)
        await client.trackSubscription(AdjustClient.Subscription(price: 1, currency: "USD", transactionId: "tx"))
        let verif = await client.verifyAndTrackPurchase(
            "ev_token",
            AdjustClient.Purchase(productId: "p", transactionId: "tx"),
            nil
        )
        #expect(verif.status == .notVerified)
        await client.setEnabled(true)
        let enabled = await client.isEnabled()
        #expect(enabled == true)
        await client.gdprForgetMe()
        await client.setThirdPartySharing(AdjustClient.ThirdPartySharing(isEnabled: false))
        await client.setMeasurementConsent(true)
    }

    @Test("custom client forwards revenue payload")
    func customForwardsRevenue() async {
        actor Spy {
            var last: AdjustClient.Revenue?
            func record(_ r: AdjustClient.Revenue) { last = r }
        }
        let spy = Spy()
        let client = AdjustClient(
            initialize: { _ in },
            trackEvent: { _, _ in },
            trackRevenue: { await spy.record($0) },
            setDeviceToken: { _ in }
        )
        let rev = AdjustClient.Revenue(amount: 0.005, currency: "USD", adUnit: "rewarded")
        await client.trackRevenue(rev)
        let captured = await spy.last
        #expect(captured?.amount == 0.005)
        #expect(captured?.adUnit == "rewarded")
    }
}
