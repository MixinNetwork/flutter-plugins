//
//  MultiWindowManager.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//

import Cocoa
import FlutterMacOS
import Foundation

extension NSRect {
  var topLeft: CGPoint {
    set {
      let screenFrameRect = NSScreen.screens[0].frame
      origin.x = newValue.x
      origin.y = screenFrameRect.height - newValue.y - size.height
    }
    get {
      let screenFrameRect = NSScreen.screens[0].frame
      return CGPoint(x: origin.x, y: screenFrameRect.height - origin.y - size.height)
    }
  }
}

enum WindowState {
  case normal
  case minimized
  case maximized
  case fullscreen
  case hidden
}

class MultiWindowManager {
  static let shared = MultiWindowManager()

  private var id: Int64 = 0
  private var windows: [Int64: BaseFlutterWindow] = [:]
  private let windowsLock = NSLock()

  func create(arguments: String, windowOptions: WindowOptions) -> Int64 {
    windowsLock.lock()
    defer { windowsLock.unlock() }

    id += 1
    let windowId = id

    let window = FlutterWindow(id: windowId, arguments: arguments, windowOptions: windowOptions)
    window.delegate = self
    window.interWindowEventChannel.methodHandler = self.handleInterWindowEvent
    windows[windowId] = window
    return windowId
  }

  func attachMainWindow(window: NSWindow, _ interWindowEventChannel: InterWindowEventChannel, _ channel: WindowEventsChannel) {
    windowsLock.lock()
    defer { windowsLock.unlock() }

    let mainWindow = BaseFlutterWindow(id: 0, window: window, interWindowEventChannel: interWindowEventChannel, windowEventsChannel: channel)
    mainWindow.interWindowEventChannel.methodHandler = self.handleInterWindowEvent
    windows[0] = mainWindow
  }

  private func handleInterWindowEvent(
    fromWindowId: Int64, targetWindowId: Int64, method: String, arguments: Any?,
    result: @escaping FlutterResult
  ) {
    windowsLock.lock()
    guard let window = self.windows[targetWindowId] else {
      windowsLock.unlock()
      result(
        FlutterError(
          code: "-1", message: "failed to find target window. \(targetWindowId)", details: nil))
      return
    }

    // Check if window is still valid
    if window.window.contentViewController == nil
      || (window.window.contentViewController as? FlutterViewController)?.engine == nil
    {
      windowsLock.unlock()
      result(
        FlutterError(
          code: "-2", message: "window engine is no longer valid \(targetWindowId)", details: nil))
      return
    }
    windowsLock.unlock()

    window.interWindowEventChannel.invokeMethod(
      fromWindowId: fromWindowId, method: method, arguments: arguments, result: result)
  }

  func handleWindowEvent(windowId: Int64, method: String, arguments: [String: Any?]?, result: @escaping FlutterResult) {
    windowsLock.lock()
    guard let window = windows[windowId] else {
      windowsLock.unlock()
      debugPrint("window \(windowId) not exists.")
      return
    }
    windowsLock.unlock()
    window.handleMethodCall(method: method, arguments: arguments, result: result)
  }

  func getAllSubWindowIds() -> [Int64] {
    windowsLock.lock()
    let ids = windows.keys.filter { $0 != 0 }
    windowsLock.unlock()
    return ids
  }

  func getWindowState(windowId: Int64) -> WindowState? {
    windowsLock.lock()
    defer { windowsLock.unlock() }
    
    guard let window = windows[windowId] else {
      return nil
    }
    
    return window.getWindowState()
  }

  func hasWindow(windowId: Int64) -> Bool {
    windowsLock.lock()
    defer { windowsLock.unlock() }
    return windows[windowId] != nil
  }
}

protocol WindowManagerDelegate: AnyObject {
  func onClose(windowId: Int64)
}

extension MultiWindowManager: WindowManagerDelegate {
  func onClose(windowId: Int64) {
    if let _ = windows[windowId] {
      // Give time for any pending messages to complete
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.windowsLock.lock()
        self.windows.removeValue(forKey: windowId)
        self.windowsLock.unlock()
      }
    }
  }
}

extension BaseFlutterWindow {
  func getWindowState() -> WindowState {
    if !window.isVisible {
      return .hidden
    } else if window.isMiniaturized {
      return .minimized
    } else if window.isZoomed {
      return .maximized
    } else if window.styleMask.contains(.fullScreen) {
      return .fullscreen
    } else {
      return .normal
    }
  }
}
