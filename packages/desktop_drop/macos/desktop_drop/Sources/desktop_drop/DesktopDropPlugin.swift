import Cocoa
import FlutterMacOS
import Carbon

// =============================================================================
// MARK: - DesktopDropServicesProvider (Dock Text/URL via NSServices)
// =============================================================================

/// Accepts text/link drops on the Dock icon via macOS Services.
///
/// Host app should install this in `applicationWillFinishLaunching`:
/// ```swift
/// if NSApp.servicesProvider == nil,
///    let cls = NSClassFromString("DesktopDropServicesProvider") as? NSObject.Type {
///   NSApp.servicesProvider = cls.init()
/// }
/// ```
@objc(DesktopDropServicesProvider)
public class DesktopDropServicesProvider: NSObject {
    private static var pending: [[String: Any]] = []

    private func enqueueAndPost(_ dict: [String: Any]) {
        DesktopDropServicesProvider.pending.append(dict)
        NotificationCenter.default.post(
            name: .desktopDropServicePayload,
            object: nil,
            userInfo: ["items": [dict]]
        )
    }

    /// Queried by the plugin to drain any pre-launch payloads.
    @objc public func desktopDropFetchPendingServicePayloads() -> [Any] {
        let copy = DesktopDropServicesProvider.pending
        DesktopDropServicesProvider.pending.removeAll()
        return copy
    }

    /// NSServices entry point (Info.plist: NSMessage = desktopDropAcceptDroppedText).
    @objc public func desktopDropAcceptDroppedText(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        // Priority: HTML → RTF → URL → plain text
        if let html = pboard.string(forType: .html), let data = html.data(using: .utf8) {
            enqueueAndPost(DropUtils.memoryItem(data: data, mimeType: "text/html; charset=utf-8", name: "Dock Dropped Text.html"))
            return
        }
        if let rtf = pboard.data(forType: .rtf) {
            enqueueAndPost(DropUtils.memoryItem(data: rtf, mimeType: "application/rtf", name: "Dock Dropped Text.rtf"))
            return
        }
        if let urlString = pboard.string(forType: .URL), let data = urlString.data(using: .utf8) {
            enqueueAndPost(DropUtils.memoryItem(data: data, mimeType: "text/uri-list", name: "Dock Dropped URL.txt"))
            return
        }
        if let s = pboard.string(forType: .string), let data = s.data(using: .utf8) {
            enqueueAndPost(DropUtils.memoryItem(data: data, mimeType: "text/plain; charset=utf-8", name: "Dock Dropped Text.txt"))
            return
        }
    }
}

// =============================================================================
// MARK: - DropUtils (Centralized Helpers)
// =============================================================================

enum DropUtils {

    /// Shared queue for asynchronous file promise operations.
    static let workQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// Prepares a standardized dictionary for a file/directory item.
    static func fileItem(for url: URL, fromPromise: Bool, seen: inout Set<String>) -> [String: Any]? {
        let path = url.path

        // De-duplicate by path
        guard seen.insert(path).inserted else { return nil }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let bookmark = createBookmarkIfNeeded(for: url, fromPromise: fromPromise)

        return [
            "path": path,
            "apple-bookmark": bookmark,
            "isDirectory": isDirectory,
            "fromPromise": fromPromise,
        ]
    }

    /// Creates a standardized dictionary for memory-backed items (text, URLs).
    static func memoryItem(data: Data, mimeType: String, name: String) -> [String: Any] {
        return [
            "data": FlutterStandardTypedData(bytes: data),
            "mimeType": mimeType,
            "name": name,
            "fromPromise": false,
        ]
    }

    /// Creates a security-scoped bookmark if needed (for files outside container).
    private static func createBookmarkIfNeeded(for url: URL, fromPromise: Bool) -> Any {
        // Promise files are written into our container/temp, no bookmark needed
        if fromPromise { return NSNull() }

        // Files in temp directory are always accessible
        if url.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            return NSNull()
        }

        // In sandboxed apps, NSHomeDirectory() points to container root.
        // Files inside the container don't need bookmarks.
        if url.path.hasPrefix(NSHomeDirectory()) {
            return NSNull()
        }

        // External files need security-scoped bookmarks
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmark
        } catch {
            return NSNull()
        }
    }

    /// Generates a unique timestamped directory for promised files.
    static func uniqueDropDestination() -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Drops", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS'Z'"
        let stamp = formatter.string(from: Date())
        let dest = base.appendingPathComponent(stamp, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true, attributes: nil)
        return dest
    }
}

// =============================================================================
// MARK: - Notification Name Extension
// =============================================================================

extension Notification.Name {
    static let desktopDropServicePayload = Notification.Name("desktop_drop.servicePayload")
}

// =============================================================================
// MARK: - DesktopDropPlugin (Core Plugin)
// =============================================================================

public class DesktopDropPlugin: NSObject, FlutterPlugin, FlutterAppLifecycleDelegate {

    private var channel: FlutterMethodChannel!
    private var pendingOpenItems: [[String: Any]] = []
    private var didFinishLaunching = false
    private var dartReady = false
    private var dropTargetInstalled = false

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "desktop_drop", binaryMessenger: registrar.messenger)
        let instance = DesktopDropPlugin()
        instance.channel = channel

        channel.setMethodCallHandler(instance.handle(_:result:))
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)

        instance.setup()
    }

    private func setup() {
        // Try to install drop target immediately
        tryInstallDropTarget()

        // Observe app activation to install drop target if view wasn't ready
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tryInstallDropTarget()
        }

        // Observe window activation for multi-window scenarios
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tryInstallDropTarget()
        }

        // Flutter macOS registers plugins after launch, so assume launched
        didFinishLaunching = true
        drainPendingServicePayloads()

        // Observe runtime service payloads (Dock text drops)
        NotificationCenter.default.addObserver(
            forName: .desktopDropServicePayload,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let items = note.userInfo?["items"] as? [[String: Any]] else { return }
            self.pendingOpenItems.append(contentsOf: items)
            self.flushPendingIfReady()
        }

        // Handle AppleEvent for text dropped on Dock icon
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenContentsEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenContents)
        )
    }

    // MARK: - Drop Target Installation

    private func tryInstallDropTarget() {
        guard !dropTargetInstalled else { return }
        guard let vc = findFlutterViewController() else { return }

        let dropTarget = DropTargetView(frame: vc.view.bounds, channel: channel)
        dropTarget.autoresizingMask = [.width, .height]
        dropTarget.registerForDrags()
        vc.view.addSubview(dropTarget)
        dropTargetInstalled = true
    }

    private func findFlutterViewController() -> FlutterViewController? {
        // Search all windows for a FlutterViewController
        for window in NSApp.windows {
            if let fvc = findFlutterVC(in: window.contentViewController) {
                return fvc
            }
        }
        // Fallback to key/main windows
        if let fvc = findFlutterVC(in: NSApp.keyWindow?.contentViewController) { return fvc }
        if let fvc = findFlutterVC(in: NSApp.mainWindow?.contentViewController) { return fvc }
        return nil
    }

    private func findFlutterVC(in viewController: NSViewController?) -> FlutterViewController? {
        guard let vc = viewController else { return nil }
        if let fvc = vc as? FlutterViewController { return fvc }
        for child in vc.children {
            if let fvc = findFlutterVC(in: child) { return fvc }
        }
        return nil
    }

    // MARK: - Method Channel Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "readyForGlobalDrops":
            drainPendingServicePayloads()
            dartReady = true
            flushPendingIfReady()
            result(true)

        case "startAccessingSecurityScopedResource":
            guard let args = call.arguments as? [String: Any],
                  let bookmarkData = (args["apple-bookmark"] as? FlutterStandardTypedData)?.data else {
                result(false)
                return
            }
            var isStale = false
            let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let success = url?.startAccessingSecurityScopedResource() ?? false
            result(success)

        case "stopAccessingSecurityScopedResource":
            guard let args = call.arguments as? [String: Any],
                  let bookmarkData = (args["apple-bookmark"] as? FlutterStandardTypedData)?.data else {
                result(true) // No-op if missing
                return
            }
            var isStale = false
            let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            url?.stopAccessingSecurityScopedResource()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Pending Items Management

    private func flushPendingIfReady() {
        guard didFinishLaunching, dartReady, !pendingOpenItems.isEmpty else { return }
        channel.invokeMethod("performOperation_macos", arguments: pendingOpenItems)
        pendingOpenItems.removeAll()
    }

    // MARK: - Lifecycle (Dock/Finder Opens)

    public func handleDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        drainPendingServicePayloads()
        flushPendingIfReady()
    }

    public func handleOpen(_ urls: [URL]) -> Bool {
        var items: [[String: Any]] = []
        var seen = Set<String>()

        for url in urls {
            if let item = DropUtils.fileItem(for: url, fromPromise: false, seen: &seen) {
                items.append(item)
            }
        }

        guard !items.isEmpty else { return false }
        pendingOpenItems.append(contentsOf: items)
        flushPendingIfReady()
        return true
    }

    // MARK: - Services & Apple Events

    private func drainPendingServicePayloads() {
        let selector = #selector(DesktopDropServicesProvider.desktopDropFetchPendingServicePayloads)

        func fetch(from obj: Any?) {
            guard let o = obj as? NSObject,
                  o.responds(to: selector),
                  let unmanaged = o.perform(selector),
                  let payloads = unmanaged.takeUnretainedValue() as? [[String: Any]] else {
                return
            }
            pendingOpenItems.append(contentsOf: payloads)
        }

        // Primary: Check the installed services provider (set by host app in AppDelegate)
        fetch(from: NSApp.servicesProvider)

        // Fallback: Check NSApp itself (in case provider was attached differently)
        fetch(from: NSApp)
    }

    @objc private func handleOpenContentsEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let desc = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        var items: [[String: Any]] = []

        func processDescriptor(_ d: NSAppleEventDescriptor) {
            if let s = d.stringValue, let data = s.data(using: .utf8) {
                items.append(DropUtils.memoryItem(
                    data: data,
                    mimeType: "text/plain; charset=utf-8",
                    name: "Dock Dropped Text.txt"
                ))
            }
        }

        if desc.descriptorType == typeAEList {
            for i in 1...desc.numberOfItems {
                if let item = desc.atIndex(i) {
                    processDescriptor(item)
                }
            }
        } else {
            processDescriptor(desc)
        }

        guard !items.isEmpty else { return }
        pendingOpenItems.append(contentsOf: items)
        flushPendingIfReady()
    }
}

// =============================================================================
// MARK: - DropTargetView (In-Window Drag Handling)
// =============================================================================

class DropTargetView: NSView {

    private let channel: FlutterMethodChannel

    init(frame frameRect: NSRect, channel: FlutterMethodChannel) {
        self.channel = channel
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drag Registration

    func registerForDrags() {
        var types: [NSPasteboard.PasteboardType] = []

        // File promises
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })

        // File URLs (modern + legacy)
        types.append(.fileURL)
        types.append(NSPasteboard.PasteboardType("NSFilenamesPboardType"))

        // Text and links (for Chromium compatibility)
        types.append(contentsOf: [.string, .html, .rtf, .URL])

        registerForDraggedTypes(types)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        channel.invokeMethod("entered", arguments: convertPointForFlutter(sender.draggingLocation))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        channel.invokeMethod("updated", arguments: convertPointForFlutter(sender.draggingLocation))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        channel.invokeMethod("exited", arguments: nil)
    }

    // MARK: - Perform Drag Operation

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        var items: [[String: Any]] = []
        var seen = Set<String>()

        // ─────────────────────────────────────────────────────────────────────
        // PRIORITY 1: Standard file URLs (public.file-url, NSFilenamesPboardType)
        // ─────────────────────────────────────────────────────────────────────
        let standardURLs = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let legacyPaths = (pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]) ?? []

        for url in standardURLs {
            if let item = DropUtils.fileItem(for: url, fromPromise: false, seen: &seen) {
                items.append(item)
            }
        }

        for path in legacyPaths {
            let url = URL(fileURLWithPath: path)
            if let item = DropUtils.fileItem(for: url, fromPromise: false, seen: &seen) {
                items.append(item)
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // PRIORITY 1.5: Chromium/Electron workarounds (VS Code, Cursor, etc.)
        // ─────────────────────────────────────────────────────────────────────
        if items.isEmpty {
            let chromiumURLs = extractChromiumPaths(from: pb)

            for url in chromiumURLs {
                // Verify file exists and is accessible
                if FileManager.default.fileExists(atPath: url.path),
                   let item = DropUtils.fileItem(for: url, fromPromise: false, seen: &seen) {
                    items.append(item)
                }
            }
        }

        // Deliver if we found items in Priority 1 or 1.5
        if !items.isEmpty {
            channel.invokeMethod("performOperation_macos", arguments: items)
            return true
        }

        // ─────────────────────────────────────────────────────────────────────
        // PRIORITY 2: File promises (async fallback)
        // ─────────────────────────────────────────────────────────────────────
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            handleFilePromises(receivers: receivers, seen: seen)
            return true
        }

        // ─────────────────────────────────────────────────────────────────────
        // PRIORITY 3 & 4: Non-file content (URLs, text)
        // ─────────────────────────────────────────────────────────────────────
        items.append(contentsOf: extractNonFileContent(from: pb))

        if !items.isEmpty {
            channel.invokeMethod("performOperation_macos", arguments: items)
            return true
        }

        return false
    }

    // MARK: - Chromium Path Extraction

    private func extractChromiumPaths(from pb: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        // 1. Check plain text for newline-separated paths (multi-file support)
        if let plainText = pb.string(forType: .string) {
            let lines = plainText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for line in lines {
                if line.hasPrefix("/") {
                    urls.append(URL(fileURLWithPath: line))
                } else if line.hasPrefix("file://"),
                          let url = URL(string: line),
                          url.isFileURL {
                    urls.append(url)
                }
            }
        }

        // 2. Fallback: public.url (single file)
        if urls.isEmpty,
           let urlString = pb.string(forType: .URL),
           let url = URL(string: urlString),
           url.isFileURL {
            urls.append(url)
        }

        // 3. Fallback: promised-file-url
        if urls.isEmpty,
           let promisedURLString = pb.string(forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")),
           let url = URL(string: promisedURLString),
           url.isFileURL {
            urls.append(url)
        }

        return urls
    }

    // MARK: - File Promise Handling

    private func handleFilePromises(receivers: [NSFilePromiseReceiver], seen: Set<String>) {
        let group = DispatchGroup()
        let dest = DropUtils.uniqueDropDestination()
        var items: [[String: Any]] = []
        let lock = NSLock()
        var mutableSeen = seen

        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: DropUtils.workQueue) { url, error in
                defer { group.leave() }

                if error != nil { return }

                lock.lock()
                if let item = DropUtils.fileItem(for: url, fromPromise: true, seen: &mutableSeen) {
                    items.append(item)
                }
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.channel.invokeMethod("performOperation_macos", arguments: items)
        }
    }

    // MARK: - Non-File Content Extraction

    private func extractNonFileContent(from pb: NSPasteboard) -> [[String: Any]] {
        var items: [[String: Any]] = []

        // Non-file URLs
        let anyURLs = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) as? [URL]) ?? []
        for url in anyURLs where !url.isFileURL {
            if let data = url.absoluteString.data(using: .utf8) {
                items.append(DropUtils.memoryItem(data: data, mimeType: "text/uri-list", name: "Dropped URL.txt"))
            }
        }

        // Text formats (only if no URLs found)
        if items.isEmpty {
            if let html = pb.string(forType: .html), let data = html.data(using: .utf8) {
                items.append(DropUtils.memoryItem(data: data, mimeType: "text/html; charset=utf-8", name: "Dropped Text.html"))
            } else if let rtf = pb.data(forType: .rtf) {
                items.append(DropUtils.memoryItem(data: rtf, mimeType: "application/rtf", name: "Dropped Text.rtf"))
            } else if let s = pb.string(forType: .string), let data = s.data(using: .utf8) {
                items.append(DropUtils.memoryItem(data: data, mimeType: "text/plain; charset=utf-8", name: "Dropped Text.txt"))
            }
        }

        return items
    }

    // MARK: - Coordinate Conversion

    private func convertPointForFlutter(_ location: NSPoint) -> [CGFloat] {
        return [location.x, bounds.height - location.y]
    }
}
