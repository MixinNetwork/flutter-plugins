import Cocoa
import FlutterMacOS

public class DesktopLifecyclePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "desktop_lifecycle", binaryMessenger: registrar.messenger)
    let instance = DesktopLifecyclePlugin(channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let channel: FlutterMethodChannel

  public init(_ channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(onApplicationActiveStateNotification), name: NSApplication.willBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(onApplicationActiveStateNotification), name: NSApplication.willResignActiveNotification, object: nil)
  }

  @objc func onApplicationActiveStateNotification(notification: Notification) {
    switch notification.name {
    case NSApplication.willBecomeActiveNotification:
      dispatchApplicationState(active: true)
      break
    case NSApplication.willResignActiveNotification:
      dispatchApplicationState(active: false)
      break
    default:
      debugPrint("invalid notification received: \(notification.name)")
    }
  }

  private func dispatchApplicationState(active: Bool) {
    channel.invokeMethod("onApplicationFocusChanged", arguments: active)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "init" {
      dispatchApplicationState(active: NSApplication.shared.isActive)
      result(nil)
      return
    }
    result(FlutterMethodNotImplemented)
  }
}
