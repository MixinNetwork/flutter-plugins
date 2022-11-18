import Cocoa
import FlutterMacOS

private func findFlutterViewController(_ viewController: NSViewController?) -> FlutterViewController? {
  guard let vc = viewController else {
    return nil
  }
  if let fvc = vc as? FlutterViewController {
    return fvc
  }
  for child in vc.children {
    let fvc = findFlutterViewController(child)
    if fvc != nil {
      return fvc
    }
  }
  return nil
}

public class DesktopDropPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    guard let app = NSApplication.shared.delegate as? FlutterAppDelegate else { return }
    guard let vc = findFlutterViewController(app.mainFlutterWindow.contentViewController) else { return }

    let channel = FlutterMethodChannel(name: "desktop_drop", binaryMessenger: registrar.messenger)
    let instance = DesktopDropPlugin()

    let d = DropTarget(frame: vc.view.bounds, channel: channel)
    d.autoresizingMask = [.width, .height]

    var dragTypes = [NSPasteboard.PasteboardType]()

    if #available(macOS 10.12, *) {
      dragTypes.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    if #available(macOS 10.13, *) {
      dragTypes.append(.fileURL)
    }
    dragTypes.append(.filePromise)
    d.registerForDraggedTypes(dragTypes)
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

  /// Directory URL used for accepting file promises.
  private lazy var destinationURL: URL = {
    let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Drops")
    try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
    return destinationURL
  }()

  /// Queue used for reading and writing file promises.
  private lazy var workQueue: OperationQueue = {
    let providerQueue = OperationQueue()
    providerQueue.qualityOfService = .userInitiated
    return providerQueue
  }()

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    var urls = [String]()

    let searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true,
    ]

    let group = DispatchGroup()

    if #available(macOS 10.12, *) {
      // retrieve NSFilePromise.
      sender.enumerateDraggingItems(options: [], for: nil, classes: [NSFilePromiseReceiver.self], searchOptions: searchOptions) { draggingItem, _, _ in
        if let filePromiseReceiver = draggingItem.item as? NSFilePromiseReceiver {
          group.enter()
          filePromiseReceiver.receivePromisedFiles(atDestination: self.destinationURL, options: [:], operationQueue: self.workQueue) { fileURL, error in
            if let error = error {
              debugPrint("error: \(error)")
            } else {
              urls.append(fileURL.path)
            }
            group.leave()
          }
          return
        }
      }
    }

    let pasteboardObjects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: searchOptions)

    pasteboardObjects?.forEach({ item in
      if let fileURL = item as? URL {
        urls.append(fileURL.path)
        return
      }
    })

    group.notify(queue: .main) {
      self.channel.invokeMethod("performOperation", arguments: urls)
    }
    return true
  }

  func convertPoint(_ location: NSPoint) -> [CGFloat] {
    return [location.x, bounds.height - location.y]
  }
}
