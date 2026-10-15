import Cocoa
import FlutterMacOS
#if SWIFT_PACKAGE
import desktop_drop_ffi
#endif

public class DesktopDropPlugin: NSObject, FlutterPlugin {
  private let destination: NativeDropTarget

  private init(destination: NativeDropTarget) {
    self.destination = destination
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    guard let view = registrar.view,
          let controller = registrar.viewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "desktop_drop", binaryMessenger: registrar.messenger)
    let destination = NativeDropTarget(frame: view.bounds, channel: channel,
                                       viewId: controller.viewIdentifier)
    destination.autoresizingMask = [.width, .height]
    view.addSubview(destination)
    registrar.addMethodCallDelegate(DesktopDropPlugin(destination: destination), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "initialize" {
      guard let args = call.arguments as? [String: Any],
            let view = args["view"] as? NSNumber,
            view.int64Value == destination.viewId else {
        result(FlutterError(code: "unsupported_view", message: "The Flutter view is not attached to this registrar", details: nil))
        return
      }
      let functions = destination.functions
      result(["view": destination.viewId, "context": functions.context,
              "register": functions.register_callback, "complete": functions.complete,
              "unregister": functions.unregister_callback])
      return
    }
    if call.method == "startAccessingSecurityScopedResource" ||
       call.method == "stopAccessingSecurityScopedResource" {
      guard let args = call.arguments as? [String: Any],
            let bytes = args["apple-bookmark"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_bookmark", message: "Expected bookmark bytes", details: nil))
        return
      }
      var stale = false
      guard let url = try? URL(resolvingBookmarkData: bytes.data, options: [.withSecurityScope],
                               relativeTo: nil, bookmarkDataIsStale: &stale) else {
        result(false)
        return
      }
      if call.method == "startAccessingSecurityScopedResource" {
        result(url.startAccessingSecurityScopedResource())
      } else {
        url.stopAccessingSecurityScopedResource()
        result(true)
      }
      return
    }
    result(FlutterMethodNotImplemented)
  }
}

private class NativeDropTarget: NSView {
  let channel: FlutterMethodChannel
  let viewId: Int64
  let functions = dd_bridge_create()
  private let itemsLock = NSLock()

  init(frame: NSRect, channel: FlutterMethodChannel, viewId: Int64) {
    self.channel = channel
    self.viewId = viewId
    super.init(frame: frame)
    var types = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    types += [.fileURL, .URL, .string, NSPasteboard.PasteboardType("NSFilenamesPboardType")]
    registerForDraggedTypes(types)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit { dd_bridge_destroy(functions.context) }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func wantsPeriodicDraggingUpdates() -> Bool { true }

  private func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
    let modern = (pasteboard.readObjects(forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    let legacy = (pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]) ?? []
    var seen = Set<String>()
    return (modern + legacy.map { URL(fileURLWithPath: $0) }).filter { seen.insert($0.path).inserted }
  }

  private func preview(_ sender: NSDraggingInfo) -> [String: Any] {
    let pb = sender.draggingPasteboard
    let files = fileURLs(pb)
    var previews: [[String: Any]] = files.map {
      ["path": $0.path, "name": $0.lastPathComponent, "isPromised": false]
    }
    var complete = true
    if files.isEmpty,
       let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
       !receivers.isEmpty {
      complete = false
      for receiver in receivers {
        let names = receiver.fileNames.isEmpty ? receiver.fileTypes.map { _ in "" } : receiver.fileNames
        previews += names.map { ["name": $0, "isPromised": true] }
      }
    }
    let urls = ((pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? [])
      .filter { !$0.isFileURL }.map { $0.absoluteString }
    let text = pb.string(forType: .string)
    var types: [String] = []
    if !previews.isEmpty { types.append("file") }
    if !urls.isEmpty { types.append("url") }
    if text != nil { types.append("text") }
    return ["types": types, "files": previews, "urls": urls,
            "text": text as Any? ?? NSNull(), "isComplete": complete]
  }

  private func event(_ sender: NSDraggingInfo, decision: DDDecision,
                     phase: Int32, offer: [String: Any], point: NSPoint) -> [String: Any] {
    return ["view": viewId, "session": Int64(sender.draggingSequenceNumber),
            "generation": decision.generation, "request": decision.request,
            "target": decision.target, "phase": phase, "x": point.x,
            "y": bounds.height - point.y, "offer": offer]
  }

  private func decide(_ sender: NSDraggingInfo, phase: Int32,
                      offer: [String: Any]) -> (DDDecision, [String: Any]) {
    let point = convert(sender.draggingLocation, from: nil)
    guard let data = try? JSONSerialization.data(withJSONObject: offer),
          let json = String(data: data, encoding: .utf8) else {
      let rejected = DDDecision(generation: 0, request: 0, target: 0)
      return (rejected, event(sender, decision: rejected, phase: phase, offer: offer, point: point))
    }
    var decision = json.withCString {
      dd_bridge_decide(functions.context, Int64(sender.draggingSequenceNumber), phase,
                       point.x, bounds.height - point.y, $0)
    }
    if !sender.draggingSourceOperationMask.contains(.copy) { decision.target = 0 }
    activeSession = Int64(sender.draggingSequenceNumber)
    let args = event(sender, decision: decision, phase: phase, offer: offer, point: point)
    channel.invokeMethod("feedback", arguments: args)
    return (decision, args)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return decide(sender, phase: 0, offer: preview(sender)).0.target > 0 ? .copy : []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    return decide(sender, phase: 1, offer: preview(sender)).0.target > 0 ? .copy : []
  }

  private var activeSession: Int64 = 0

  override func draggingExited(_ sender: NSDraggingInfo?) {
    channel.invokeMethod("exit", arguments: ["view": viewId,
      "session": sender.map { Int64($0.draggingSequenceNumber) } ?? activeSession,
      "generation": dd_bridge_generation(functions.context)])
  }

  override func draggingEnded(_ sender: NSDraggingInfo) { draggingExited(sender) }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let offer = preview(sender)
    let (decision, original) = decide(sender, phase: 2, offer: offer)
    guard decision.target > 0 else { return false }
    let pb = sender.draggingPasteboard
    let urls = fileURLs(pb)
    var items: [[String: Any]] = []
    var seen = Set<String>()
    let group = DispatchGroup()

    func push(_ url: URL, promised: Bool) {
      itemsLock.lock()
      defer { itemsLock.unlock() }
      guard seen.insert(url.path).inserted else { return }
      let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      let temporary = FileManager.default.temporaryDirectory.path
      let inside = promised || url.path.hasPrefix(temporary + "/")
      let bookmark = inside ? nil : try? url.bookmarkData(options: [.withSecurityScope],
        includingResourceValuesForKeys: nil, relativeTo: nil)
      items.append(["path": url.path, "name": url.lastPathComponent,
                    "isDirectory": isDirectory, "isPromised": promised,
                    "apple-bookmark": bookmark.map { FlutterStandardTypedData(bytes: $0) } as Any? ?? NSNull()])
    }

    if !urls.isEmpty {
      urls.forEach { push($0, promised: false) }
    } else if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty {
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("Drops", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      } catch {
        return false
      }
      let workQueue = OperationQueue()
      workQueue.qualityOfService = .userInitiated
      workQueue.isSuspended = true
      for receiver in receivers {
        receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: workQueue) { url, error in
          defer { group.leave() }
          if let error = error { NSLog("desktop_drop: file promise failed: %@", error.localizedDescription); return }
          push(url, promised: true)
        }
        // Calling in a promise populates fileNames. fileTypes can contain only
        // unique types for legacy sources, so it is not a file count.
        // Keep callbacks suspended until every expected completion is entered.
        for _ in 0..<max(1, receiver.fileNames.count) { group.enter() }
      }
      workQueue.isSuspended = false
    }
    group.notify(queue: .main) { [weak self] in
      guard let self = self, self.window != nil,
            dd_bridge_generation(self.functions.context) == decision.generation else { return }
      var delivered = offer
      delivered["files"] = items
      delivered["isComplete"] = true
      var args = original
      args["offer"] = delivered
      self.channel.invokeMethod("drop", arguments: args)
    }
    return true
  }
}
