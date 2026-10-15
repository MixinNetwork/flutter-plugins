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
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "desktop_drop",
            dependencies: ["desktop_drop_ffi",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
        .target(
            name: "desktop_drop_ffi",
            exclude: ["vendor/README.md", "vendor/LICENSE", "vendor/dart_api_dl.c"],
            publicHeadersPath: "include"
        )
    ],
    cxxLanguageStandard: .cxx17
)
