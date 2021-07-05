import Cocoa
import FlutterMacOS

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
        case "absoluteUrlString":
            absoluteUrlString(result: result)
        case "writeUrl":
            if let arguments = call.arguments as? [Any?], let urlString = arguments.first as? String {
                writeUrl(urlString, result: result)
            } else {
                result(false)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func image(result: FlutterResult){
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            result(nil)
            return
        }
        result(image.png)
    }

    private func absoluteUrlString(result: FlutterResult) {
        guard let url = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil)?.first as? NSURL else {
            result(nil)
            return
        }
        result(url.absoluteString)
    }

    private func writeUrl(_ urlString: String, result: FlutterResult){
        guard let url = NSURL(string: urlString) else {
            result(false)
            return
        }
        NSPasteboard.general.clearContents()
        result(NSPasteboard.general.writeObjects([url]))
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
