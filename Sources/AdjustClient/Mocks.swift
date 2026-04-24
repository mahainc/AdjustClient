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
        initialize:        { _ in },
        trackEvent:        { _, _ in },
        trackRevenue:      { _ in },
        setDeviceToken:    { _ in },
        attributionStream: { .finished },
        deeplinkStream:    { .finished }
    )
}
