import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Install Services provider so Dock text drops are accepted when launching the app
    if NSApp.servicesProvider == nil,
       let cls = NSClassFromString("DesktopDropServicesProvider") as? NSObject.Type {
      NSApp.servicesProvider = cls.init()
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
