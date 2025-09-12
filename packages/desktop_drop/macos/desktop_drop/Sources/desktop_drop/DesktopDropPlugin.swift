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
    guard let flutterView = registrar.view else { return }
    guard let flutterWindow = flutterView.window else { return }
    guard let vc = findFlutterViewController(flutterWindow.contentViewController) else { return }

    let channel = FlutterMethodChannel(name: "desktop_drop", binaryMessenger: registrar.messenger)

    let instance = DesktopDropPlugin()
      
      channel.setMethodCallHandler(instance.handle(_:result:))
      
    let d = DropTarget(frame: vc.view.bounds, channel: channel)
    d.autoresizingMask = [.width, .height]

    // Register for all relevant types (promises, URLs, and legacy filename arrays)
    var types = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    types.append(.fileURL) // public.file-url
    types.append(NSPasteboard.PasteboardType("NSFilenamesPboardType")) // legacy multi-file array
    d.registerForDraggedTypes(types)

    vc.view.addSubview(d)

    registrar.addMethodCallDelegate(instance, channel: channel)
  }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult){
 
      if call.method ==  "startAccessingSecurityScopedResource"{
            let map = call.arguments as! NSDictionary 
            var isStale: Bool = false

          let bookmarkByte = map["apple-bookmark"] as! FlutterStandardTypedData
          let bookmark = bookmarkByte.data
            
            let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            let suc = url?.startAccessingSecurityScopedResource()
            result(suc) 
            return
      }

      if call.method ==  "stopAccessingSecurityScopedResource"{
            let map = call.arguments as! NSDictionary 
            var isStale: Bool = false 
          let bookmarkByte = map["apple-bookmark"] as! FlutterStandardTypedData
          let bookmark = bookmarkByte.data
            let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            url?.stopAccessingSecurityScopedResource()
            result(true)
            return
      }

      Swift.print("method not found: \(call.method)")
      result(FlutterMethodNotImplemented)
      return
  }

   
}

class DropTarget: NSView {
  private let channel: FlutterMethodChannel
  private let itemsLock = NSLock()

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

  /// Create a per-drop destination for promised files (avoids name collisions).
  private func uniqueDropDestination() -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("Drops", isDirectory: true)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd_HHmmss_SSS'Z'"
    let stamp = formatter.string(from: Date())
    let dest = base.appendingPathComponent(stamp, isDirectory: true)
    try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true, attributes: nil)
    return dest
  }

  /// Queue used for reading and writing file promises.
  private lazy var workQueue: OperationQueue = {
    let providerQueue = OperationQueue()
    providerQueue.qualityOfService = .userInitiated
    return providerQueue
  }()

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pb = sender.draggingPasteboard
    let dest = uniqueDropDestination()
    var items: [[String: Any]] = []
    var seen = Set<String>()
    let group = DispatchGroup()

    func push(url: URL, fromPromise: Bool) {
      let path = url.path
      itemsLock.lock(); defer { itemsLock.unlock() }

      // de-dupe safely under lock
      if !seen.insert(path).inserted { return }

      let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
      let isDirectory: Bool = values?.isDirectory ?? false

      // Only create a security-scoped bookmark for items outside our container.
      let bundleID = Bundle.main.bundleIdentifier ?? ""
      let containerRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/\(bundleID)", isDirectory: true)
        .path
      let tmpPath = FileManager.default.temporaryDirectory.path
      let isInsideContainer = path.hasPrefix(containerRoot) || path.hasPrefix(tmpPath)

      let bmData: Any
      if isInsideContainer {
        bmData = NSNull()
      } else {
        let bm = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        bmData = bm ?? NSNull()
      }
      items.append([
        "path": path,
        "apple-bookmark": bmData,
        "isDirectory": isDirectory,
        "fromPromise": fromPromise,
      ])
    }

    // Prefer real file URLs if they exist; only fall back to promises
    let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    let legacyList = (pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]) ?? []

    if !urls.isEmpty || !legacyList.isEmpty {
      // 1) Modern file URLs
      urls.forEach { push(url: $0, fromPromise: false) }
      // 2) Legacy filename array used by some apps
      legacyList.forEach { push(url: URL(fileURLWithPath: $0), fromPromise: false) }
    } else {
      // 3) Handle file promises (e.g., VS Code, browsers, Mail)
      if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
         !receivers.isEmpty {
        for r in receivers {
          group.enter()
          r.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: self.workQueue) { url, error in
            defer { group.leave() }
            if let error = error {
              debugPrint("NSFilePromiseReceiver error: \(error)")
              return
            }
            push(url: url, fromPromise: true)
          }
        }
      }
    }

    group.notify(queue: .main) {
      self.channel.invokeMethod("performOperation_macos", arguments: items)
    }
    return true
  }

  func convertPoint(_ location: NSPoint) -> [CGFloat] {
    return [location.x, bounds.height - location.y]
  }
}
