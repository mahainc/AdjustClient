// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AdjustClient",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .singleTargetLibrary("AdjustClient"),
        .singleTargetLibrary("AdjustClientLive"),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", branch: "main"),
        .package(url: "https://github.com/adjust/ios_sdk.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "AdjustClient",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
        .target(
            name: "AdjustClientLive",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "AdjustSdk", package: "ios_sdk"),
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
