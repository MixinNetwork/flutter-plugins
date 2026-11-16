import Flutter
import UIKit

@objc(PasteboardPlugin)
public class PasteboardPlugin: NSObject, FlutterPlugin {
  // Pasteboard access can block, e.g. while another app still provides the
  // data, so image and writeImage run off the main thread, in call order.
  private static let queue = DispatchQueue(label: "one.mixin.pasteboard", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pasteboard", binaryMessenger: registrar.messenger())
    let instance = PasteboardPlugin()
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

  private func image(result: @escaping FlutterResult) {
    Self.queue.async {
      let data = UIPasteboard.general.image?.pngData()
      DispatchQueue.main.async { result(data) }
    }
  }

  private func files(result: FlutterResult) {
    result(nil)
  }

  private func writeFiles(_ files: [String], result: FlutterResult) {
    result(nil)
  }
  
  private func writeImageToPasteboard(_ data: Data, result: @escaping FlutterResult) {
    Self.queue.async {
      UIPasteboard.general.image = UIImage(data: data)
      DispatchQueue.main.async { result(nil) }
    }
  }
}

