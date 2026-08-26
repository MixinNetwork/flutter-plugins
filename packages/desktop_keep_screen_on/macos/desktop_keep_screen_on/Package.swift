// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "desktop_keep_screen_on",
    platforms: [
        .macOS("10.11")
    ],
    products: [
        .library(name: "desktop-keep-screen-on", targets: ["desktop_keep_screen_on"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "desktop_keep_screen_on",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
