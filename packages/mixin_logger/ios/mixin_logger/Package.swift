// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mixin_logger",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        // `mixin_logger` is an FFI plugin whose Dart bindings load the native
        // code from a dynamic framework, so the product is built as a dynamic
        // library rather than being statically linked into the app binary.
        //
        // The product is named `mixin-logger` (with a hyphen) because Flutter's
        // generated `FlutterGeneratedPluginSwiftPackage` references plugin
        // products by the package name with underscores replaced by hyphens.
        // The framework SPM builds is therefore `mixin-logger.framework`; the
        // Dart loader in `lib/src/write_to_file_ffi.dart` accepts both this name
        // and the CocoaPods `mixin_logger.framework` name.
        .library(name: "mixin-logger", type: .dynamic, targets: ["mixin_logger"])
    ],
    targets: [
        .target(
            name: "mixin_logger"
        )
    ]
)
