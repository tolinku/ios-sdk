// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TolinkuSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "TolinkuSDK",
            targets: ["TolinkuSDK"]
        )
    ],
    targets: [
        .target(
            name: "TolinkuSDK",
            path: "Sources/TolinkuSDK"
        ),
        .testTarget(
            name: "TolinkuSDKTests",
            dependencies: ["TolinkuSDK"],
            path: "Tests/TolinkuSDKTests"
        )
    ]
)
