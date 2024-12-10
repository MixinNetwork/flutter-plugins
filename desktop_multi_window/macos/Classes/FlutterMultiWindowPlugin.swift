import Cocoa
import FlutterMacOS

public class FlutterMultiWindowPlugin: NSObject, FlutterPlugin {
  static func registerInternal(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "mixin.one/flutter_multi_window", binaryMessenger: registrar.messenger)
    let instance = FlutterMultiWindowPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    registerInternal(with: registrar)

    guard let window = registrar.view!.window else {
      debugPrint("failed to find flutter main window")
      return
    }

    let mainWindowChannel = WindowChannel.register(with: registrar, windowId: 0)
    MultiWindowManager.shared.attachMainWindow(window: window, mainWindowChannel)
  }

  public typealias OnWindowClosedCallback = (Int64) -> Void
  static var onWindowClosedCallback: OnWindowClosedCallback?

  public typealias OnWindowCreatedCallback = (FlutterViewController, Int64) -> Void
  static var onWindowCreatedCallback: OnWindowCreatedCallback?

  public static func setOnWindowCreatedCallback(_ callback: @escaping OnWindowCreatedCallback) {
    onWindowCreatedCallback = callback
  }

  public static func setOnWindowClosedCallback(_ callback: @escaping OnWindowClosedCallback) {
    onWindowClosedCallback = callback
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createWindow":
      let arguments = call.arguments as? String
      let windowId = MultiWindowManager.shared.create(arguments: arguments ?? "")
      result(windowId)
    case "show":
      let windowId = call.arguments as! Int64
      MultiWindowManager.shared.show(windowId: windowId)
      result(nil)
    case "hide":
      let windowId = call.arguments as! Int64
      MultiWindowManager.shared.hide(windowId: windowId)
      result(nil)
    case "close":
      let windowId = call.arguments as! Int64
      MultiWindowManager.shared.close(windowId: windowId)
      result(nil)
    case "center":
      let windowId = call.arguments as! Int64
      MultiWindowManager.shared.center(windowId: windowId)
      result(nil)
    case "setFrame":
      let arguments = call.arguments as! [String: Any?]
      let windowId = arguments["windowId"] as! Int64
      let left = arguments["left"] as! Double
      let top = arguments["top"] as! Double
      let width = arguments["width"] as! Double
      let height = arguments["height"] as! Double
      let rect = NSRect(x: left, y: top, width: width, height: height)
      MultiWindowManager.shared.setFrame(windowId: windowId, frame: rect)
      result(nil)
    case "setTitle":
      let arguments = call.arguments as! [String: Any?]
      let windowId = arguments["windowId"] as! Int64
      let title = arguments["title"] as! String
      MultiWindowManager.shared.setTitle(windowId: windowId, title: title)
      result(nil)
	case "resizable":
	  let arguments = call.arguments as! [String: Any?]
	  let windowId = arguments["windowId"] as! Int64
	  let resizable = arguments["resizable"] as! Bool
	  MultiWindowManager.shared.resizable(windowId: windowId, resizable: resizable)
	  result(nil)
    case "setFrameAutosaveName":
      let arguments = call.arguments as! [String: Any?]
      let windowId = arguments["windowId"] as! Int64
      let frameAutosaveName = arguments["name"] as! String
      MultiWindowManager.shared.setFrameAutosaveName(windowId: windowId, name: frameAutosaveName)
      result(nil)
    case "getAllSubWindowIds":
      let subWindowIds = MultiWindowManager.shared.getAllSubWindowIds()
      result(subWindowIds)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
