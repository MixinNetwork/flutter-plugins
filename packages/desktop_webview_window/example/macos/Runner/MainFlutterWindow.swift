import Cocoa
import FlutterMacOS

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
