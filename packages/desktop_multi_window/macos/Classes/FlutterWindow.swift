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

        self.isReleasedWhenClosed = true
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

    init(windowId: WindowId, windowArgument: String, window: NSWindow) {
        self.windowId = windowId
        self.windowArgument = windowArgument
        self.window = window
        super.init()

        // https://github.com/MixinNetwork/flutter-plugins/issues/412
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeOcclusionState),
            name: NSApplication.willBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeOcclusionState),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
