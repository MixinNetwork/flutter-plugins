import Cocoa
import FlutterMacOS
import Foundation

typealias WindowId = String

extension WindowId {
    static func generate() -> WindowId {
        return UUID().uuidString
    }
}

class CustomWindow: NSWindow {

    init(configuration: WindowConfiguration) {
        super.init(
            contentRect: NSRect(x: 10, y: 10, width: 800, height: 600),
            styleMask: [.miniaturizable, .closable, .titled, .resizable], backing: .buffered,
            defer: false)

        self.isReleasedWhenClosed = false
    }

    deinit {
        debugPrint("Child window deinit")
    }

}

class FlutterWindow: NSObject {
    let windowId: WindowId
    let windowArgument: String
    private(set) var window: NSWindow
    private var channel: FlutterMethodChannel?

    private var willBecomeActiveObserver: NSObjectProtocol?
    private var didResignActiveObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(windowId: WindowId, windowArgument: String, window: NSWindow) {
        self.windowId = windowId
        self.windowArgument = windowArgument
        self.window = window
        super.init()

        willBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.didChangeOcclusionState(notification)
        }

        didResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.didChangeOcclusionState(notification)
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [windowId] _ in
            MultiWindowManager.shared.removeWindow(windowId: windowId)
        }
    }

    deinit {
        if let willBecomeActiveObserver = willBecomeActiveObserver {
            NotificationCenter.default.removeObserver(willBecomeActiveObserver)
        }
        if let didResignActiveObserver = didResignActiveObserver {
            NotificationCenter.default.removeObserver(didResignActiveObserver)
        }
        if let closeObserver = closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    @objc func didChangeOcclusionState(_ notification: Notification) {
        if let controller = window.contentViewController as? FlutterViewController {
            controller.engine.handleDidChangeOcclusionState(notification)
        }
    }

    func setChannel(_ channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func notifyWindowEvent(_ event: String, data: [String: Any]) {
        if let channel = channel {
            channel.invokeMethod(event, arguments: data)
        } else {
            debugPrint("Channel not set for window \(windowId), cannot notify event \(event)")
        }
    }

    func handleWindowMethod(method: String, arguments: Any?, result: @escaping FlutterResult) {
        switch method {
        case "window_show":
            window.makeKeyAndOrderFront(nil)
            window.setIsVisible(true)
            NSApp.activate(ignoringOtherApps: true)
            result(nil)
        case "window_hide":
            window.orderOut(nil)
            result(nil)
        default:
            result(FlutterError(code: "-1", message: "unknown method \(method)", details: nil))
        }
    }

}
