import Cocoa
import FlutterMacOS

public class DesktopDropPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    guard let app = NSApplication.shared.delegate as? FlutterAppDelegate else { return }
    guard let vc = app.mainFlutterWindow.contentViewController else { return }

    let channel = FlutterMethodChannel(name: "desktop_drop", binaryMessenger: registrar.messenger)
    let instance = DesktopDropPlugin()

    debugPrint("bounds: \(vc.view.bounds)")
    let d = DropTarget(frame: vc.view.bounds, channel: channel)
    d.autoresizingMask = [.width, .height]
    if #available(macOS 10.13, *) {
      d.registerForDraggedTypes([.fileURL])
    } else {
      debugPrint("unsupport file URL")
    }
    vc.view.addSubview(d)

    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}

class DropTarget: NSView {
  private let channel: FlutterMethodChannel

  init(frame frameRect: NSRect, channel: FlutterMethodChannel) {
    self.channel = channel
    super.init(frame: frameRect)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    channel.invokeMethod("entered", arguments: convertPoint(sender.draggingLocation))
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    channel.invokeMethod("updated", arguments: convertPoint(sender.draggingLocation))
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    channel.invokeMethod("exited", arguments: nil)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    var urls = [String]()

    if let items = sender.draggingPasteboard.pasteboardItems {
      for item in items {
        if #available(macOS 10.13, *) {
          if let alias = item.string(forType: .fileURL) {
            urls.append(URL(fileURLWithPath: alias).standardized.absoluteString)
          }
        } else {
        }
      }
    }

    channel.invokeMethod("performOpeartion", arguments: urls)
    return true
  }

  func convertPoint(_ location: NSPoint) -> [CGFloat] {
    return [location.x, bounds.height - location.y]
  }
}
