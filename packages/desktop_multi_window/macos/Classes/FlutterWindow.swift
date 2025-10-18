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
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: configuration.getStyleMask(), backing: .buffered, defer: false)
        
        self.title = configuration.title
        self.titleVisibility = configuration.hideTitleBar ? .hidden : .visible
        self.titlebarAppearsTransparent = configuration.hideTitleBar
        self.isReleasedWhenClosed = true
        
        setFrameTopLeftPoint(configuration.frame.toTopLeftPoint())
        setContentSize(configuration.frame.toContentSize())

    }

   
}

class FlutterWindow {
    let windowId: WindowId
    let windowArgument: String
    private(set) var window: NSWindow
    
    init(windowId: WindowId, windowArgument: String, window: NSWindow) {
        self.windowId = windowId
        self.windowArgument = windowArgument
        self.window = window
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
