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

extension AdjustClient {
    /// Auto-renewable IAP subscription event. Mirrors `ADJAppStoreSubscription` —
    /// passed to `trackSubscription(_:)` to forward subscription revenue to Adjust.
    public struct Subscription: Sendable, Equatable {
        public let price: Decimal
        public let currency: String
        public let transactionId: String
        public let transactionDate: Date?
        public let salesRegion: String?
        public let callbackParameters: [String: String]
        public let partnerParameters: [String: String]

        public init(
            price: Decimal,
            currency: String,
            transactionId: String,
            transactionDate: Date? = nil,
            salesRegion: String? = nil,
            callbackParameters: [String: String] = [:],
            partnerParameters: [String: String] = [:]
        ) {
            self.price = price
            self.currency = currency
            self.transactionId = transactionId
            self.transactionDate = transactionDate
            self.salesRegion = salesRegion
            self.callbackParameters = callbackParameters
            self.partnerParameters = partnerParameters
        }
    }
}

extension AdjustClient {
    /// IAP purchase to verify (and optionally track) via Adjust's receipt-validation
    /// backend. Mirrors `ADJAppStorePurchase`.
    public struct Purchase: Sendable, Equatable {
        public let productId: String
        public let transactionId: String

        public init(productId: String, transactionId: String) {
            self.productId = productId
            self.transactionId = transactionId
        }
    }
}

extension AdjustClient {
    /// Result returned by `verifyAndTrackPurchase`. Mirrors `ADJPurchaseVerificationResult`.
    public struct PurchaseVerification: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            case success
            case failure
            case unknown
            case notVerified

            public init(rawAdjustValue: String?) {
                switch rawAdjustValue {
                case "success":      self = .success
                case "failure":      self = .failure
                case "not_verified": self = .notVerified
                default:             self = .unknown
                }
            }
        }

        public let status: Status
        public let code: Int
        public let message: String?

        public init(status: Status, code: Int, message: String?) {
            self.status = status
            self.code = code
            self.message = message
        }
    }
}

extension AdjustClient {
    /// Granular third-party-sharing settings for `setThirdPartySharing(_:)`.
    /// Mirrors `ADJThirdPartySharing` — used to opt in/out of CCPA-class data
    /// sharing globally or per partner.
    ///
    /// - `isEnabled` — `nil` lets the server decide; `false` disables sharing
    ///   entirely; `true` enables it.
    /// - `granularOptions` — `[partnerName: [key: value]]`, e.g.
    ///   `["facebook": ["consent": "granted"]]`.
    /// - `partnerSharingSettings` — `[partnerName: [setting: bool]]`, e.g.
    ///   `["snapchat": ["everything": false]]`.
    public struct ThirdPartySharing: Sendable, Equatable {
        public let isEnabled: Bool?
        public let granularOptions: [String: [String: String]]
        public let partnerSharingSettings: [String: [String: Bool]]

        public init(
            isEnabled: Bool? = nil,
            granularOptions: [String: [String: String]] = [:],
            partnerSharingSettings: [String: [String: Bool]] = [:]
        ) {
            self.isEnabled = isEnabled
            self.granularOptions = granularOptions
            self.partnerSharingSettings = partnerSharingSettings
        }
    }
}
