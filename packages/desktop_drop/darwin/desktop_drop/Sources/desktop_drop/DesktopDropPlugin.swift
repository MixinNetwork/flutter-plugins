#if os(macOS)
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
    let transport = FfiTransport(engine: Int64(Int(bitPattern: Unmanaged.passUnretained(controller.engine).toOpaque())))
    let destination = NativeDropTarget(frame: view.bounds, transport: transport,
                                       viewId: controller.viewIdentifier)
    destination.autoresizingMask = [.width, .height]
    view.addSubview(destination)
    let plugin = DesktopDropPlugin(destination: destination)
    transport.handler = { [weak plugin] call, result in
      guard let plugin = plugin else { result(FlutterMethodNotImplemented); return }
      plugin.handle(call, result: result)
    }
    registrar.publish(plugin)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "readSource" {
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_source", message: "Expected a dropped source", details: nil)); return
      }
      destination.readSource(args, result: result)
      return
    }
    if call.method == "initialize" {
      guard let args = call.arguments as? [String: Any],
            let view = args["view"] as? NSNumber,
            view.int64Value == destination.viewId else {
        result(FlutterError(code: "unsupported_view", message: "The Flutter view is not attached to this registrar", details: nil))
        return
      }
      destination.resetSources()
      result(["view": destination.viewId, "context": destination.context])
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
  let transport: FfiTransport
  let viewId: Int64
  let context = dd_bridge_create()
  private enum Source {
    case image(NSPasteboardItem, NSPasteboard.PasteboardType)
    case promise(Promise, Int)
  }
  private final class Promise {
    let receiver: NSFilePromiseReceiver
    let names: [String]
    var started = false
    var results: [Result<URL, Error>?]
    var waiters: [Int: [(Result<URL, Error>) -> Void]] = [:]
    init(_ receiver: NSFilePromiseReceiver, names: [String]) {
      self.receiver = receiver; self.names = names
      self.results = Array(repeating: nil, count: names.count)
    }
  }
  private final class Session: DropResources {
    // AppKit pasteboards can change independently of a retained drag session.
    let pasteboard: NSPasteboard
    let changeCount: Int
    var sources: [Source]
    init(generation: Int64, pasteboard: NSPasteboard, sources: [Source]) {
      self.pasteboard = pasteboard
      self.changeCount = pasteboard.changeCount; self.sources = sources
      super.init(generation: generation)
    }
    override func release() {
      guard !released else { return }
      super.release()
      for source in sources {
        if case .promise(let promise, _) = source {
          let waiters = promise.waiters.values.flatMap { $0 }
          promise.waiters.removeAll()
          for waiter in waiters {
            waiter(.failure(NSError(domain: "desktop_drop.source_expired", code: 1)))
          }
        }
      }
      sources.removeAll()
    }
  }
  private var sources: [Source] = []
  private var sessions: [Int64: Session] = [:]
  private let promiseQueue = OperationQueue()

  init(frame: NSRect, transport: FfiTransport, viewId: Int64) {
    self.transport = transport
    self.viewId = viewId
    super.init(frame: frame)
    var types = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    types += [.fileURL, .URL, .string, .html, .png, .tiff, NSPasteboard.PasteboardType("NSFilenamesPboardType")]
    registerForDraggedTypes(types)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit { releaseSources(); dd_bridge_destroy(context) }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func wantsPeriodicDraggingUpdates() -> Bool { true }

  private func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
    let modern = (pasteboard.readObjects(forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    let legacy = (pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]) ?? []
    var seen = Set<String>()
    return (modern + legacy.map { URL(fileURLWithPath: $0) }).filter { seen.insert($0.path).inserted }
  }

  private func promiseReceivers(_ sender: NSDraggingInfo) -> [NSFilePromiseReceiver] {
    var receivers: [NSFilePromiseReceiver] = []
    // Prefer an existing URL for each pasteboard item, while preserving promises
    // belonging to other items in the same drag.
    sender.enumerateDraggingItems(options: [], for: self,
      classes: [NSURL.self, NSFilePromiseReceiver.self],
      searchOptions: [.urlReadingFileURLsOnly: true]) { item, _, _ in
        if let receiver = item.item as? NSFilePromiseReceiver { receivers.append(receiver) }
      }
    return receivers
  }

  private func imageItems(_ pasteboard: NSPasteboard) -> [(NSPasteboardItem, NSPasteboard.PasteboardType)] {
    let promises = Set(NSFilePromiseReceiver.readableDraggedTypes)
    return (pasteboard.pasteboardItems ?? []).compactMap { item in
      // An item's image bytes can be an alternate representation of its file.
      if item.types.contains(.fileURL) || item.types.contains(where: { promises.contains($0.rawValue) }) { return nil }
      guard let type = [NSPasteboard.PasteboardType.png, .tiff].first(where: { item.types.contains($0) }) else { return nil }
      return (item, type)
    }
  }

  private var previewSession = -1
  private var cachedPreview: [String: Any]?

  private func preview(_ sender: NSDraggingInfo, capture: Bool = false) -> [String: Any] {
    let pb = sender.draggingPasteboard
    if !capture, previewSession == sender.draggingSequenceNumber,
       let offer = cachedPreview { return offer }
    if capture {
      sources.removeAll()
    }
    var sourceIndex = 0
    let files = fileURLs(pb)
    var previews: [[String: Any]] = files.map {
      ["path": $0.path, "name": $0.lastPathComponent, "isPromised": false,
       "isDirectory": (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false]
    }
    var complete = true
    let receivers = promiseReceivers(sender)
    if !receivers.isEmpty {
      complete = false
      for receiver in receivers {
        let names = receiver.fileNames.isEmpty ? receiver.fileTypes.map { _ in "" } : receiver.fileNames
        let promise = Promise(receiver, names: names)
        for (index, name) in names.enumerated() {
          let type = receiver.fileTypes.count == names.count ? receiver.fileTypes[index] : receiver.fileTypes.first ?? ""
          var metadata: [String: Any] = ["name": name, "isPromised": true, "source": sourceIndex,
                                        "resolvePath": true,
                                        "isDirectory": type == "public.folder" || type == "public.directory"]
          if let mime = dropMimeType(type) { metadata["mimeType"] = mime }
          previews.append(metadata)
          sourceIndex += 1
          if capture { sources.append(.promise(promise, index)) }
        }
      }
    }
    let urls = ((pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? [])
      .filter { !$0.isFileURL }.map { $0.absoluteString }
    for (item, type) in imageItems(pb) {
      previews.append(["name": type == .png ? "image.png" : "image.tiff",
                       "mimeType": type == .png ? "image/png" : "image/tiff", "source": sourceIndex])
      sourceIndex += 1
      if capture { sources.append(.image(item, type)) }
    }
    var strings: [[String: Any]] = []
    for (type, mime) in [(NSPasteboard.PasteboardType.string, "text/plain"), (.html, "text/html")] {
      if let value = pb.string(forType: type) {
        strings.append(["mimeType": mime, "value": value])
      }
    }
    if !urls.isEmpty { strings.append(["mimeType": "text/uri-list", "value": urls.joined(separator: "\r\n")]) }
    var mask = sender.draggingSourceOperationMask
    // AppKit cannot postpone the final move effect until Dart finishes reading.
    // Do not let the source delete files that the application has not read yet.
    if !previews.isEmpty { mask.remove(.move) }
    let operations = [(NSDragOperation.copy, "copy"), (.move, "move"), (.link, "link")]
      .compactMap { mask.contains($0.0) ? $0.1 : nil }
    let offer: [String: Any] = ["files": previews, "strings": strings,
      "allowedOperations": operations, "isComplete": complete]
    previewSession = sender.draggingSequenceNumber
    cachedPreview = offer
    return offer
  }

  private func operationMask(_ sender: NSDraggingInfo, offer: [String: Any]) -> Int {
    var mask = sender.draggingSourceOperationMask
    if !(offer["files"] as? [[String: Any]] ?? []).isEmpty { mask.remove(.move) }
    return (mask.contains(.copy) ? 1 : 0) | (mask.contains(.move) ? 2 : 0) |
      (mask.contains(.link) ? 4 : 0)
  }

  private func event(_ sender: NSDraggingInfo, decision: DDDecision,
                     phase: Int32, offer: [String: Any], point: NSPoint) -> [String: Any] {
    var args = dropEvent(view: viewId, session: Int64(sender.draggingSequenceNumber),
                         phase: phase, point: CGPoint(x: point.x, y: bounds.height - point.y),
                         mask: operationMask(sender, offer: offer), decision: decision)
    if phase == 2 { args["offer"] = offer }
    return args
  }

  private func decide(_ sender: NSDraggingInfo, phase: Int32,
                      offer: [String: Any]) -> (DDDecision, [String: Any]) {
    let point = convert(sender.draggingLocation, from: nil)
    let mask = operationMask(sender, offer: offer)
    var decision = decideDrop(context: context, session: Int64(sender.draggingSequenceNumber),
                              phase: phase, point: CGPoint(x: point.x, y: bounds.height - point.y),
                              mask: mask, offer: offer, full: phase != 1)
    let operation = nativeOperation(decision.operation)
    if operation.isEmpty || !sender.draggingSourceOperationMask.contains(operation) ||
       (phase == 2 && operation != activeOperation) {
      decision.target = 0
      decision.operation = 0
    }
    activeSession = Int64(sender.draggingSequenceNumber)
    let args = event(sender, decision: decision, phase: phase, offer: offer, point: point)
    var feedback = args
    feedback.removeValue(forKey: "offer")
    transport.invoke("feedback", arguments: feedback)
    return (decision, args)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    activeOperation = nativeOperation(decide(sender, phase: 0, offer: preview(sender)).0.operation)
    return activeOperation
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    activeOperation = nativeOperation(decide(sender, phase: 1, offer: preview(sender)).0.operation)
    return activeOperation
  }

  private var activeSession: Int64 = 0
  private var activeOperation: NSDragOperation = []

  private func nativeOperation(_ operation: Int32) -> NSDragOperation {
    switch operation {
    case 1: return .copy
    case 2: return .move
    case 3: return .link
    default: return []
    }
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    activeOperation = []
    transport.invoke("exit", arguments: ["view": viewId,
      "session": sender.map { Int64($0.draggingSequenceNumber) } ?? activeSession,
      "generation": dd_bridge_generation(context)])
  }

  override func draggingEnded(_ sender: NSDraggingInfo) { draggingExited(sender) }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

  private func expired() -> FlutterError {
    FlutterError(code: "source_expired", message: "Dropped source is no longer available", details: nil)
  }

  func resetSources() {
    releaseSources(); previewSession = -1; cachedPreview = nil
  }

  private func releaseSources() {
    for session in sessions.values { session.release() }
    sessions.removeAll(); sources.removeAll()
  }

  private func receive(_ promise: Promise, index: Int, session: Session,
                       completion: @escaping (Result<URL, Error>) -> Void) {
    if let result = promise.results[index] { completion(result); return }
    guard !session.released else {
      completion(.failure(NSError(domain: "desktop_drop.source_expired", code: 1))); return
    }
    promise.waiters[index, default: []].append(completion)
    if promise.started { return }
    promise.started = true
    do {
      _ = try session.temporaryDirectory()
    } catch {
      for index in promise.results.indices { promise.results[index] = .failure(error) }
      let waiters = promise.waiters.values.flatMap { $0 }; promise.waiters.removeAll()
      for waiter in waiters { waiter(.failure(error)) }
      return
    }
    // AppKit receives a receiver's entire group once, even when the application
    // asks for only one member. All receivers in this drop share a destination.
    session.pendingLoads += 1
    promise.receiver.receivePromisedFiles(atDestination: session.directory!, options: [:],
                                          operationQueue: promiseQueue) { url, error in
      DispatchQueue.main.async {
        let index = promise.names.indices.first {
          promise.results[$0] == nil && promise.names[$0] == url.lastPathComponent
        } ?? promise.results.firstIndex(where: { $0 == nil })
        guard let index = index else { return }
        let value: Result<URL, Error>
        if let error = error { value = .failure(error) } else { value = .success(url) }
        promise.results[index] = value
        let waiters = promise.waiters.removeValue(forKey: index) ?? []
        for waiter in waiters { waiter(value) }
        if promise.results.allSatisfy({ $0 != nil }) {
          session.pendingLoads -= 1; session.cleanup()
        }
      }
    }
  }

  func readSource(_ args: [String: Any], result: @escaping FlutterResult) {
    let id = (args["session"] as? NSNumber)?.int64Value ?? -1
    let session = sessions[id]
    let current = session != nil && !session!.released &&
      (args["generation"] as? NSNumber)?.int64Value == session!.generation &&
      dd_bridge_generation(context) == session!.generation
    let operation = args["op"] as? String ?? ""
    guard current, let session = session else { result(expired()); return }
    if session.read(args, result: result) { return }
    let index = (args["source"] as? NSNumber)?.intValue ?? -1
    guard session.sources.indices.contains(index) else { result(expired()); return }
    switch session.sources[index] {
    case .promise(let promise, let index):
      guard operation == "resolve" else { result(FlutterMethodNotImplemented); return }
      receive(promise, index: index, session: session) { value in
        guard !session.released else {
          result(FlutterError(code: "source_expired", message: "Dropped source was released", details: nil)); return
        }
        switch value {
        case .success(let url): result(url.path)
        case .failure(let error): result(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
        }
      }
    case .image(let item, let type):
      guard session.pasteboard.changeCount == session.changeCount,
            let data = item.data(forType: type) else { result(expired()); return }
      if operation == "stat" { result(["length": data.count]); return }
      guard operation == "open" else { result(FlutterMethodNotImplemented); return }
      session.open(data, args: args, result: result)
    }
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let offer = preview(sender, capture: true)
    let (decision, args) = decide(sender, phase: 2, offer: offer)
    guard decision.target > 0 else { sources.removeAll(); return false }
    let id = Int64(sender.draggingSequenceNumber)
    let session = Session(generation: decision.generation, pasteboard: sender.draggingPasteboard, sources: sources)
    sessions[id] = session
    sources.removeAll()
    // Bookmark bytes belong only to the accepted drop payload. The
    // decision and feedback offers carry metadata only.
    var files = offer["files"] as? [[String: Any]] ?? []
    for index in files.indices {
      guard let path = files[index]["path"] as? String else { continue }
      let url = URL(fileURLWithPath: path)
      if let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                             includingResourceValuesForKeys: nil, relativeTo: nil) {
        files[index]["apple-bookmark"] = FlutterStandardTypedData(bytes: bookmark)
      }
    }
    var dropOffer = offer
    dropOffer["files"] = files
    var dropArgs = args
    dropArgs["offer"] = dropOffer
    transport.invoke("drop", arguments: dropArgs) { [weak self] _ in
      if self?.sessions[id] === session { self?.sessions.removeValue(forKey: id) }
      session.release()
    }
    return true
  }
}

#endif
