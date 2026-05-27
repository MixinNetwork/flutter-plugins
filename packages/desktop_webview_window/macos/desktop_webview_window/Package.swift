// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "desktop_webview_window",
    platforms: [
        .macOS("10.13")
    ],
    products: [
        .library(name: "desktop-webview-window", targets: ["desktop_webview_window"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "desktop_webview_window",
            dependencies: [],
            resources: [
                .process("WebViewLayoutController.xib"),
            ]
        )
    ]
)
