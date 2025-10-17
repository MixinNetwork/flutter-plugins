import Cocoa
import FlutterMacOS

public class FlutterMultiWindowPlugin: NSObject, FlutterPlugin {
  static func registerInternal(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mixin.one/flutter_multi_window", binaryMessenger: registrar.messenger)
    let instance = FlutterMultiWindowPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    registerInternal(with: registrar)
    guard let app = NSApplication.shared.delegate as? FlutterAppDelegate else {
      debugPrint(
        "failed to find flutter main window, application delegate is not FlutterAppDelegate")
      return
    }
    guard let window = app.mainFlutterWindow else {
      debugPrint("failed to find flutter main window")
      return
    }
    let mainWindowEventsChannel = WindowEventsChannel.register(returns: registrar)
    let mainWindowInterWindowEventChannel = InterWindowEventChannel.register(
      with: registrar, windowId: 0)
    MultiWindowManager.shared.attachMainWindow(
      window: window, mainWindowInterWindowEventChannel, mainWindowEventsChannel)
  }

  public typealias OnWindowCreatedCallback = (FlutterViewController) -> Void
  static var onWindowCreatedCallback: OnWindowCreatedCallback?

  public static func setOnWindowCreatedCallback(_ callback: @escaping OnWindowCreatedCallback) {
    onWindowCreatedCallback = callback
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createWindow":
      if let args = call.arguments as? [String: Any],
        let optionsJson = args["options"] as? [String: Any],
        let macosJson = optionsJson["macos"] as? [String: Any],
        let windowOptions = WindowOptions(json: macosJson)
      {
        let arguments = call.arguments as? String
        let windowId = MultiWindowManager.shared.create(
          arguments: arguments ?? "", windowOptions: windowOptions)
        result(windowId)
      } else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Could not parse macOS window options.",
            details: nil))
      }
    case "getAllSubWindowIds":
      let subWindowIds = MultiWindowManager.shared.getAllSubWindowIds()
      result(subWindowIds)
    default:
      guard let arguments = call.arguments as? [String: Any?] else {
        result(FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Method call arguments must be a dictionary",
          details: nil
        ))
        return
      }
      
      guard let windowId = arguments["windowId"] as? Int64 else {
        result(FlutterError(
          code: "INVALID_WINDOW_ID",
          message: "Window ID must be provided and must be an integer",
          details: nil
        ))
        return
      }
      
      // Verify the window exists before attempting to handle the event
      if !MultiWindowManager.shared.hasWindow(windowId: windowId) {
        result(FlutterError(
          code: "WINDOW_NOT_FOUND",
          message: "No window found with ID: \(windowId)",
          details: nil
        ))
        return
      }
      MultiWindowManager.shared.handleWindowEvent(
        windowId: windowId,
        method: call.method,
        arguments: arguments,
        result: result
      )
    }
  }
}
