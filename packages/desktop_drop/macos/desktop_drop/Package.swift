// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "desktop_drop",
    platforms: [
        .macOS("10.13")
    ],
    products: [
        .library(name: "desktop-drop", targets: ["desktop_drop"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "desktop_drop",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
