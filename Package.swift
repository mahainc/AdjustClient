// swift-tools-version: 6.1
import PackageDescription

/// The `Funnel` trait's name, shared by its declaration below and by every product
/// condition that gates on it. The matching `#if Funnel` in the conformer cannot
/// reference this — a compiler condition is not a Swift expression — but these two
/// manifest-level uses can, and a typo in either would silently stop gating.
let funnelTrait = "Funnel"

let package = Package(
    name: "AdjustClient",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .singleTargetLibrary("AdjustClient"),
        .singleTargetLibrary("AdjustClientLive"),
    ],
    // The funnel conformer is opt-in. A consumer that never hands this client to
    // `FunnelClient.live(marketing:)` should not pay for FunnelClient + LogClient
    // in its dependency graph — and that is the common case: the one fleet app
    // that depends on this package builds its funnel without a `marketing` stack,
    // so it registers `adjustClient` and never reaches the conformer.
    //
    // `#if canImport(FunnelClient)` cannot do this: it is evaluated after
    // resolution, so the dependency is already fetched and built by the time the
    // compiler sees the condition. A trait gates the edge itself.
    //
    // Off by default, so adding this package never widens a graph by surprise:
    //   .package(url: "…/AdjustClient.git", from: "3.2.0")                  // no funnel
    //   .package(url: "…/AdjustClient.git", from: "3.2.0", traits: ["Funnel"])
    traits: [
        .default(enabledTraits: []),
        Trait(
            name: funnelTrait,
            description: "Conform AdjustClient to FunnelClient's attribution, marketing-event and IAP-revenue ports."
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths.git", from: "1.5.0"),
        .package(url: "https://github.com/adjust/ios_sdk.git", from: "5.0.0"),
        .package(url: "https://github.com/mahainc/FunnelClient.git", from: "9.0.0"),
        .package(url: "https://github.com/mahainc/LogClient.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "AdjustClient",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "CasePaths", package: "swift-case-paths"),
            ]
        ),
        // The only target that knows FunnelClient exists, and only when the
        // `Funnel` trait is on. AdjustClient itself stays a plain Adjust SDK
        // wrapper any consumer can use without the funnel.
        .target(
            name: "AdjustClientLive",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "AdjustSdk", package: "ios_sdk"),
                .product(
                    name: "FunnelClient",
                    package: "FunnelClient",
                    condition: .when(traits: [funnelTrait])
                ),
                // Imported only by AdjustClient+Funnel.swift, so it follows the
                // same trait.
                .product(
                    name: "LogClient",
                    package: "LogClient",
                    condition: .when(traits: [funnelTrait])
                ),
                "AdjustClient",
            ]
        ),
        .testTarget(
            name: "AdjustClientTests",
            dependencies: ["AdjustClient"]
        ),
    ]
)

extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
