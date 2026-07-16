// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mixin_logger",
    platforms: [
        .iOS("11.0"),
        .macOS("10.11")
    ],
    products: [
        // The Dart bindings load this product as a dynamic framework.
        .library(name: "mixin-logger", type: .dynamic, targets: ["mixin_logger"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "mixin_logger",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
