import Foundation

extension AdjustClient {
    public enum Environment: Sendable, Equatable {
        case sandbox
        case production
    }
}

extension AdjustClient {
    public enum LogLevel: Sendable, Equatable {
        case verbose
        case debug
        case info
        case warn
        case error
        case suppress
    }
}

extension AdjustClient {
    public struct Config: Sendable, Equatable {
        public let appToken: String
        public let environment: Environment
        public let logLevel: LogLevel
        /// Adjust event token used when forwarding ad-revenue events. `nil` → skip.
        public let revenueEventToken: String?

        public init(
            appToken: String,
            environment: Environment,
            logLevel: LogLevel = .info,
            revenueEventToken: String? = nil
        ) {
            self.appToken = appToken
            self.environment = environment
            self.logLevel = logLevel
            self.revenueEventToken = revenueEventToken
        }
    }
}

extension AdjustClient {
    /// Cross-SDK-neutral ad-revenue payload used to bridge GoogleMobileAds' `AdValue` into Adjust
    /// without leaking GoogleMobileAds types into this client's interface.
    public struct Revenue: Sendable, Equatable {
        public let amount: Double
        public let currency: String
        public let adUnit: String
        public let network: String
        public let source: String
        public let placement: String
        public let impressions: Int

        public init(
            amount: Double,
            currency: String,
            adUnit: String,
            network: String = "AdMob",
            source: String = "admob_sdk",
            placement: String = "default",
            impressions: Int = 1
        ) {
            self.amount = amount
            self.currency = currency
            self.adUnit = adUnit
            self.network = network
            self.source = source
            self.placement = placement
            self.impressions = impressions
        }
    }
}

extension AdjustClient {
    /// Install-attribution payload emitted by Adjust's `adjustAttributionChanged(_:)`
    /// delegate callback. Cross-SDK-neutral — consumers fan this into analytics
    /// (e.g. `AnalyticClient.setUserProperty("acquisition_source", attr.network)`)
    /// without importing `AdjustSdk`.
    ///
    /// All fields mirror `ADJAttribution` one-to-one and are optional because
    /// Adjust reports them as nullable.
    public struct Attribution: Sendable, Equatable {
        public let trackerToken: String?
        public let trackerName: String?
        public let network: String?
        public let campaign: String?
        public let adgroup: String?
        public let creative: String?
        public let clickLabel: String?
        public let costType: String?
        public let costAmount: Double?
        public let costCurrency: String?

        public init(
            trackerToken: String? = nil,
            trackerName: String? = nil,
            network: String? = nil,
            campaign: String? = nil,
            adgroup: String? = nil,
            creative: String? = nil,
            clickLabel: String? = nil,
            costType: String? = nil,
            costAmount: Double? = nil,
            costCurrency: String? = nil
        ) {
            self.trackerToken = trackerToken
            self.trackerName = trackerName
            self.network = network
            self.campaign = campaign
            self.adgroup = adgroup
            self.creative = creative
            self.clickLabel = clickLabel
            self.costType = costType
            self.costAmount = costAmount
            self.costCurrency = costCurrency
        }
    }
}

// MARK: - Backward-compatibility shims (delete once consumers migrate)

public typealias AdjustEnvironment = AdjustClient.Environment
public typealias AdjustLogLevel = AdjustClient.LogLevel
public typealias AdjustConfig = AdjustClient.Config
public typealias AdjustRevenue = AdjustClient.Revenue
