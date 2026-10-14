import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    #if DEBUG
    // Example-only native geometry fixture for integration tests.
    let testChannel = FlutterMethodChannel(
      name: "webview_example/native_test", binaryMessenger: flutterViewController.engine.binaryMessenger)
    testChannel.setMethodCallHandler { call, result in
      if call.method == "titlebar",
         let args = call.arguments as? [String: Any],
         let title = args["title"] as? String,
         let operation = args["operation"] as? String,
         let window = NSApp.windows.first(where: { $0.title == title }),
         let controller = window.contentViewController?.children.compactMap({ $0 as? FlutterViewController }).first {
        let channel = FlutterMethodChannel(
          name: "webview_example/titlebar_test", binaryMessenger: controller.engine.binaryMessenger)
        channel.invokeMethod(operation, arguments: nil, result: result)
        return
      }
      if call.method == "inspect",
         let args = call.arguments as? [String: Any],
         let title = args["title"] as? String,
         let window = NSApp.windows.first(where: { $0.title == title }),
         let content = window.contentView {
        content.layoutSubtreeIfNeeded()
        func findWebView(_ view: NSView) -> WKWebView? {
          if let webView = view as? WKWebView { return webView }
          return view.subviews.compactMap { findWebView($0) }.first
        }
        guard let webView = findWebView(content) else {
          result(FlutterError(code: "test_webview_missing", message: "WebView not found", details: nil))
          return
        }
        result([
          "contentHeight": content.bounds.height,
          "webHeight": webView.bounds.height,
          "webWidth": webView.bounds.width,
          "contentWidth": content.bounds.width,
        ])
        return
      }
      guard call.method == "resize",
            let args = call.arguments as? [String: Any],
            let title = args["title"] as? String,
            let width = args["width"] as? Double,
            let height = args["height"] as? Double,
            let window = NSApp.windows.first(where: { $0.title == title }) else {
        result(FlutterError(code: "test_window_missing", message: "Native test window not found", details: nil))
        return
      }
      window.setContentSize(NSSize(width: width, height: height))
      result(nil)
    }
    #endif

    super.awakeFromNib()
  }
}
