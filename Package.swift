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
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths.git", from: "1.5.0"),
        .package(url: "https://github.com/adjust/ios_sdk.git", from: "5.0.0"),
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
        .target(
            name: "AdjustClientLive",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "CasePaths", package: "swift-case-paths"),
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
