import Flutter
import UIKit

public class SwiftPasteboardPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pasteboard", binaryMessenger: registrar.messenger())
    let instance = SwiftPasteboardPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "image":
      image(result: result)
    case "files":
      files(result: result)
    case "writeFiles":
      if let arguments = call.arguments as? [String] {
        writeFiles(arguments, result: result)
      } else {
        result(FlutterError(code: "0", message: "arguments is not String list.", details: nil))
      }
    case "writeImage":
      if let data = call.arguments as? FlutterStandardTypedData {
        writeImageToPasteboard(data.data, result: result)
      } else {
        result(FlutterError(code: "0", message: "arguments is not data", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func image(result: FlutterResult) {
    let image = UIPasteboard.general.image
    let data =  image?.pngData()
    result(data)
  }

  private func files(result: FlutterResult) {
    result(nil)
  }

  private func writeFiles(_ files: [String], result: FlutterResult) {
    result(nil)
  }
  
  private func writeImageToPasteboard(_ data: Data, result: FlutterResult) {
    let image = UIImage(data: data)
    UIPasteboard.general.image = image
    result(nil)
  }
}

