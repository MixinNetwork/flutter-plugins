import Cocoa
import FlutterMacOS
import AppKit

public class PasteboardPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pasteboard", binaryMessenger: registrar.messenger)
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

  private func writeImageToPasteboard(_ data: Data, result: FlutterResult) {
    let image = NSImage(data: data) ?? NSImage()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image as NSImage])
    result(nil)
  }

  private func image(result: FlutterResult) {
    guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
      result(nil)
      return
    }
    result(image.png)
  }

  private func files(result: FlutterResult) {
    guard let urlList = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) else {
      result(nil)
      return
    }

    var resultFiles: [String] = []

    urlList.forEach { url in
      if let path = (url as? NSURL)?.path {
        resultFiles.append(path)
      }
    }
    result(resultFiles)
  }

  private func writeFiles(_ files: [String], result: FlutterResult) {
    var urls: [NSURL] = []

    files.forEach { file in
      urls.append(NSURL(fileURLWithPath: file))
    }
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.writeObjects(urls) {
      result(nil)
    } else {
      result(FlutterError(code: "0", message: "failed to write pasteboard objects", details: nil))
    }
  }
}

extension NSBitmapImageRep {
  var png: Data? { representation(using: .png, properties: [:]) }
}

extension Data {
  var bitmap: NSBitmapImageRep? { NSBitmapImageRep(data: self) }
}

extension NSImage {
  var png: Data? { tiffRepresentation?.bitmap?.png }
}
