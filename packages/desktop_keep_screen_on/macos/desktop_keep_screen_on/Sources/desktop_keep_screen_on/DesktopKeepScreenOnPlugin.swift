import Cocoa
import FlutterMacOS
import IOKit
import IOKit.pwr_mgt

public class DesktopKeepScreenOnPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "one.mixin/desktop_keep_screen_on", binaryMessenger: registrar.messenger)
    let instance = DesktopKeepScreenOnPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private var assertionID: IOPMAssertionID?

  private func releaseAssertion() {
    if let assertionID = assertionID {
      IOPMAssertionRelease(assertionID)
      self.assertionID = nil
    }
  }

  private func requiredPreventSleep() -> Bool {
    let reasonForActivity = "long running task" as CFString
    var assertionID: IOPMAssertionID = 0
    let success = IOPMAssertionCreateWithName(
      kIOPMAssertionTypeNoDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reasonForActivity,
      &assertionID
    )
    if success != kIOReturnSuccess {
      return false
    }
    self.assertionID = assertionID
    return true
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setPreventSleep":
      let arguments = call.arguments as! [String: Any]
      let preventSleep = arguments["preventSleep"] as! Bool
      if preventSleep && assertionID == nil {
        if !requiredPreventSleep() {
          result(FlutterError(code: "failed", message: "Failed to prevent sleep", details: nil))
          return
        }
      } else {
        releaseAssertion()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
