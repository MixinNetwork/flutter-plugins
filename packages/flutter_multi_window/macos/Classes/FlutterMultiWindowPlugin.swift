import Cocoa
import FlutterMacOS

public class FlutterMultiWindowPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "mixin.one/flutter_multi_window", binaryMessenger: registrar.messenger)
    let instance = FlutterMultiWindowPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createWindow":
      let windowId = MultiWindowManager.shared.create()
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
    case "setSize":
      let arguments = call.arguments as! [String: Any?]
      let windowId = arguments["windowId"] as! Int64
      let width = arguments["width"] as! Int
      let height = arguments["height"] as! Int
      MultiWindowManager.shared.setSize(windowId: windowId, width: width, height: height)
      result(nil)
    case "center":
      let windowId = call.arguments as! Int64
      MultiWindowManager.shared.center(windowId: windowId)
      result(nil)
    case "setPosition":
      let arguments = call.arguments as! [String: Any?]
      let windowId = arguments["windowId"] as! Int64
      let x = arguments["x"] as! Int
      let y = arguments["y"] as! Int
      MultiWindowManager.shared.setPosition(windowId: windowId, x: x, y: y)
      result(nil)
    case "setTitle":
      let arguments = call.arguments as! [String: Any?]
      let windowId = arguments["windowId"] as! Int64
      let title = arguments["title"] as! String
      MultiWindowManager.shared.setTitle(windowId: windowId, title: title)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
