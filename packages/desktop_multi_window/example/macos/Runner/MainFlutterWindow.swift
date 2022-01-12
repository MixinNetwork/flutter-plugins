import Cocoa
import FlutterMacOS
import desktop_multi_window
import path_provider_macos

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // Register the plugin which you want access from other isolate.
      PathProviderPlugin.register(with: controller.registrar(forPlugin: "PathProviderPlugin"))
    }

    super.awakeFromNib()
  }
}
