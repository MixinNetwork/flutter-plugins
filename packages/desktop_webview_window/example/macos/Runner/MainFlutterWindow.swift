import Cocoa
import FlutterMacOS
import desktop_webview_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Before the first browser is created.
    TestComposer.install()

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    TestComposer.registerChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
