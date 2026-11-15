// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TolinkuSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
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
            path: "Sources/TolinkuSDK",
            resources: [
                // A manifest that is not declared here is not shipped. Swift
                // Package Manager copies declared resources into a bundle the
                // app embeds, and Xcode's privacy report reads .xcprivacy files
                // out of those bundles; a file sitting in Sources and named
                // nowhere reaches nobody. Matches the Flutter plugin's
                // Package.swift, which ships the same file the same way.
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "TolinkuSDKTests",
            dependencies: ["TolinkuSDK"],
            path: "Tests/TolinkuSDKTests"
        )
    ]
)
