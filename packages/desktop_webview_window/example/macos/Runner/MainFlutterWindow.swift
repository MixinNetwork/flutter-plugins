import Cocoa
import FlutterMacOS
import WebKit
import desktop_webview_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = try! DesktopWebviewWindowPlugin.createMainViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    #if DEBUG
    // Example-only native geometry fixture for integration tests.
    let testChannel = FlutterMethodChannel(
      name: "webview_example/native_test", binaryMessenger: flutterViewController.engine.binaryMessenger)
    testChannel.setMethodCallHandler { call, result in
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
          "titled": window.styleMask.contains(.titled),
          "fullSizeContentView": window.styleMask.contains(.fullSizeContentView),
          "transparentTitlebar": window.titlebarAppearsTransparent,
          "webTopInWindow": webView.convert(webView.bounds, to: nil).maxY,
          "contentLayoutTop": window.contentLayoutRect.maxY,
          "closeButtonVisible": window.standardWindowButton(.closeButton).map { !$0.isHidden } ?? false,
          "canBecomeKey": window.canBecomeKey,
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
