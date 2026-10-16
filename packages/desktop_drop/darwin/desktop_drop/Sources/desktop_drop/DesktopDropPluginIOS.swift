#if os(iOS)
import UIKit
import Flutter
#if SWIFT_PACKAGE
import desktop_drop_ffi
#endif

public final class DesktopDropPlugin: NSObject, FlutterPlugin, UIDropInteractionDelegate {
  private struct Item {
    let provider: NSItemProvider
    let fileType: String?
    let strings: [(type: String, mime: String)]
  }
  private final class Session: DropResources {
    let providers: [NSItemProvider]
    var files: [[String: Any]]
    var results: [Result<URL, Error>?]
    var strings: [[String: Any]]
    var progress: [Progress] = []
    let group = DispatchGroup()
    var complete = true
    init(generation: Int64, providers: [NSItemProvider], files: [[String: Any]], strings: [[String: Any]]) {
      self.providers = providers
      self.files = files
      self.strings = strings
      results = Array(repeating: nil, count: files.count)
      super.init(generation: generation)
    }
    override func release() {
      guard !released else { return }
      super.release()
      progress.forEach { if !$0.isFinished { $0.cancel() } }
      progress.removeAll()
    }
  }
  private let registrar: FlutterPluginRegistrar
  private var transport: FfiTransport!
  private let context = dd_bridge_create()
  private weak var host: UIView?
  private var interaction: UIDropInteraction?
  private var active: UIDropSession?
  private var serial: Int64 = 0
  private var itemIDs: [ObjectIdentifier] = []
  private var items: [Item] = []
  private var offer: [String: Any] = [:]
  private var offerChanged = true
  private var operation: UIDropOperation = .cancel
  private var sessions: [Int64: Session] = [:]

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    // Registration can precede the FlutterViewController. Match the engine's
    // stable messenger, then attach the interaction when Dart initializes.
    let messenger = registrar.messenger()
    transport = FfiTransport(engine: 0, matches: { engine in
      guard let pointer = UnsafeRawPointer(bitPattern: Int(engine)) else { return false }
      let owner = Unmanaged<FlutterEngine>.fromOpaque(pointer).takeUnretainedValue()
      return owner.binaryMessenger === messenger
    })
    transport.handler = { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      self.handle(call, result: result)
    }
  }
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.publish(DesktopDropPlugin(registrar: registrar))
  }
  deinit {
    sessions.values.forEach { $0.release() }
    dd_bridge_destroy(context)
  }
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    if let interaction = interaction { host?.removeInteraction(interaction) }
    interaction = nil
    host = nil
    reset()
    transport = nil
  }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "initialize" {
      guard let args = call.arguments as? [String: Any],
            (args["view"] as? NSNumber)?.int64Value == 0,
            let controller = registrar.viewController as? FlutterViewController else {
        result(dropError("unsupported_view", "Flutter view is not attached")); return
      }
      let view = controller.view!
      if host !== view {
        if let interaction = interaction { host?.removeInteraction(interaction) }
        let interaction = UIDropInteraction(delegate: self)
        view.addInteraction(interaction)
        self.interaction = interaction
        host = view
      }
      reset()
      result(["view": Int64(0), "context": context])
      return
    }
    guard call.method == "readSource", let args = call.arguments as? [String: Any] else {
      result(FlutterMethodNotImplemented); return
    }
    let id = (args["session"] as? NSNumber)?.int64Value ?? -1
    guard let session = sessions[id], !session.released,
          (args["generation"] as? NSNumber)?.int64Value == session.generation,
          dd_bridge_generation(context) == session.generation else { result(dropError()); return }
    let index = (args["source"] as? NSNumber)?.intValue ?? -1
    guard args["op"] as? String == "resolve", session.results.indices.contains(index),
          let value = session.results[index] else { result(dropError()); return }
    switch value {
    case .success(let url): result(url.path)
    case .failure(let error): result(dropError("read_failed", error.localizedDescription))
    }
  }
  private func reset() {
    sessions.values.forEach { $0.release() }
    sessions.removeAll()
    active = nil
    itemIDs.removeAll()
    items.removeAll()
    offer.removeAll()
    operation = .cancel
  }
  private func preview(_ session: UIDropSession) {
    if active !== session {
      active = session
      serial += 1
      itemIDs.removeAll()
    }
    let ids = session.items.map { ObjectIdentifier($0) }
    guard ids != itemIDs else { return }
    itemIDs = ids
    items = session.items.map { drag in
      let provider = drag.itemProvider
      let types = provider.registeredTypeIdentifiers
      let folder = types.first { dropTypeConforms($0, to: "public.directory") }
      let content = types.first {
        (dropTypeConforms($0, to: "public.data") || dropTypeConforms($0, to: "public.content")) &&
          !dropTypeConforms($0, to: "public.text") && !dropTypeConforms($0, to: "public.url")
      }
      let fileURL = types.first { dropTypeConforms($0, to: "public.file-url") }
      let named = !(provider.suggestedName ?? "").isEmpty
      var strings: [(String, String)] = []
      if let type = types.first(where: { dropTypeConforms($0, to: "public.plain-text") }) { strings.append((type, "text/plain")) }
      if let type = types.first(where: { dropTypeConforms($0, to: "public.html") }) { strings.append((type, "text/html")) }
      if let type = types.first(where: { dropTypeConforms($0, to: "public.url") && !dropTypeConforms($0, to: "public.file-url") }) {
        strings.append((type, "text/uri-list"))
      }
      let namedData = named ? types.first {
        dropTypeConforms($0, to: "public.data") && !dropTypeConforms($0, to: "public.url")
      } : nil
      let file = folder ?? content ?? fileURL ?? namedData ?? (strings.isEmpty ? types.first : nil)
      return Item(provider: provider, fileType: file, strings: strings)
    }
    var files: [[String: Any]] = []
    var strings: [[String: Any]] = []
    for item in items {
      if let type = item.fileType {
        var file: [String: Any] = ["name": item.provider.suggestedName ?? "", "source": files.count,
          "resolvePath": true, "isPromised": true, "isDirectory": dropTypeConforms(type, to: "public.directory")]
        if let mime = dropMimeType(type) { file["mimeType"] = mime }
        files.append(file)
      }
      strings += item.strings.map { ["mimeType": $0.mime, "value": NSNull()] }
    }
    offer = ["files": files, "strings": strings, "isComplete": false, "allowedOperations": ["copy"]]
    offerChanged = true
  }
  private func choose(_ session: UIDropSession, phase: Int32) -> (DDDecision, [String: Any]) {
    preview(session)
    guard let host = host else {
      return (DDDecision(generation: dd_bridge_generation(context), request: 0, target: 0, operation: 0), [:])
    }
    let point = session.location(in: host)
    var decision = decideDrop(context: context, session: serial, phase: phase, point: point,
                              mask: 1, offer: offer, full: phase != 1 || offerChanged)
    offerChanged = false
    // Keep the source intact until the application's asynchronous reads finish.
    if decision.operation != 1 { decision.target = 0; decision.operation = 0 }
    let args = dropEvent(view: 0, session: serial, phase: phase, point: point, mask: 1, decision: decision)
    transport.invoke("feedback", arguments: args)
    return (decision, args)
  }
  public func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    preview(session)
    return !(offer["files"] as? [[String: Any]] ?? []).isEmpty ||
      !(offer["strings"] as? [[String: Any]] ?? []).isEmpty
  }
  public func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
    operation = choose(session, phase: 0).0.target > 0 ? .copy : .cancel
  }
  public func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
    operation = choose(session, phase: 1).0.target > 0 ? .copy : .cancel
    return UIDropProposal(operation: operation)
  }
  public func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) { exit(session) }
  public func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
    exit(session)
    if active === session { active = nil; items.removeAll(); itemIDs.removeAll() }
  }
  private func exit(_ session: UIDropSession) {
    guard active === session else { return }
    operation = .cancel
    transport?.invoke("exit", arguments: ["view": Int64(0), "session": serial,
                                         "generation": dd_bridge_generation(context)])
  }
  public func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    guard operation == .copy else { return }
    let (decision, args) = choose(session, phase: 2)
    guard decision.target > 0 else { return }
    let id = serial
    let resources = Session(generation: decision.generation, providers: items.map { $0.provider }, files: offer["files"] as? [[String: Any]] ?? [],
                            strings: offer["strings"] as? [[String: Any]] ?? [])
    sessions[id] = resources
    var fileIndex = 0
    var stringIndex = 0
    // UIKit permits provider requests only inside this callback. Start transfers
    // now; the app consumes the retained copies through the existing XFile API.
    for item in items {
      if let type = item.fileType {
        loadFile(item.provider, type: type, index: fileIndex, session: resources)
        fileIndex += 1
      }
      for string in item.strings {
        loadString(item.provider, type: string.type, mime: string.mime, index: stringIndex, session: resources)
        stringIndex += 1
      }
    }
    resources.group.notify(queue: .main) { [weak self] in
      guard let self = self, !resources.released,
            dd_bridge_generation(self.context) == resources.generation else { resources.release(); return }
      var args = args
      args["offer"] = ["files": resources.files, "strings": resources.strings,
                        "isComplete": resources.complete, "allowedOperations": ["copy"]]
      self.transport.invoke("drop", arguments: args) { [weak self] _ in
        if self?.sessions[id] === resources { self?.sessions.removeValue(forKey: id) }
        resources.release()
      }
    }
  }
  private func loadFile(_ provider: NSItemProvider, type: String, index: Int, session: Session) {
    let directory: URL
    do {
      directory = try session.temporaryDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch { session.results[index] = .failure(error); session.complete = false; return }
    session.pendingLoads += 1
    session.group.enter()
    let receive: (URL?, Error?) -> Void = { url, error in
      let value = Result<URL, Error> {
        if let error = error { throw error }
        guard let url = url else { throw NSError(domain: "desktop_drop.read_failed", code: 1) }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var copyError: Error?
        var destination: URL?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
          do {
            let copy = directory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: copy)
            destination = copy
          } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError as NSError? { throw error }
        guard let destination = destination else { throw NSError(domain: "desktop_drop.read_failed", code: 2) }
        return destination
      }
      DispatchQueue.main.async {
        session.results[index] = value
        switch value {
        case .success(let url):
          session.files[index]["isDirectory"] = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
          if (session.files[index]["name"] as? String ?? "").isEmpty { session.files[index]["name"] = url.lastPathComponent }
        case .failure: session.complete = false
        }
        session.pendingLoads -= 1
        session.cleanup()
        session.group.leave()
      }
    }
    if dropTypeConforms(type, to: "public.file-url") {
      session.progress.append(provider.loadObject(ofClass: NSURL.self) { value, error in
        receive(value as? URL, error)
      })
    } else {
      session.progress.append(provider.loadFileRepresentation(forTypeIdentifier: type, completionHandler: receive))
    }
  }
  private func loadString(_ provider: NSItemProvider, type: String, mime: String, index: Int, session: Session) {
    session.group.enter()
    let receive: (String?, Error?) -> Void = { text, error in
      DispatchQueue.main.async {
        if error == nil, let text = text { session.strings[index]["value"] = text }
        else { session.complete = false }
        session.group.leave()
      }
    }
    if mime == "text/uri-list" {
      session.progress.append(provider.loadObject(ofClass: NSURL.self) { value, error in
        receive((value as? URL)?.absoluteString, error)
      })
    } else {
      session.progress.append(provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
        let text = data.flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .utf16) }
        receive(text, error)
      })
    }
  }
}
#endif
