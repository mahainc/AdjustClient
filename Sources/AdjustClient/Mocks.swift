import Dependencies

extension DependencyValues {
    public var adjustClient: AdjustClient {
        get { self[AdjustClient.self] }
        set { self[AdjustClient.self] = newValue }
    }
}

extension AdjustClient: TestDependencyKey {
    public static var testValue: Self { Self() }
    public static var previewValue: Self { Self() }
}

extension AdjustClient {
    public static let noop: Self = .init(
        initialize:             { _ in },
        trackEvent:             { _, _ in },
        trackRevenue:           { _ in },
        setDeviceToken:         { _ in },
        processDeeplink:        { _, _ in },
        resolveDeeplink:        { _, _ in nil },
        trackSubscription:      { _ in },
        verifyAndTrackPurchase: { _, _, _ in
            PurchaseVerification(status: .notVerified, code: -1, message: nil)
        },
        setEnabled:             { _ in },
        isEnabled:              { true },
        gdprForgetMe:           { },
        setThirdPartySharing:   { _ in },
        setMeasurementConsent:  { _ in },
        attributionStream:      { .finished },
        deeplinkStream:         { .finished }
    )
}
