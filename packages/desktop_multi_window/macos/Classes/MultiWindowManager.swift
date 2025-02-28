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

class MultiWindowManager {
  static let shared = MultiWindowManager()

  private var id: Int64 = 0

  private var windows: [Int64: BaseFlutterWindow] = [:]

  func create(arguments: String, windowOptions: WindowOptions) -> Int64 {
    id += 1
    let windowId = id

    let window = FlutterWindow(id: windowId, arguments: arguments, windowOptions: windowOptions)
    window.delegate = self
    window.windowChannel.methodHandler = self.handleMethodCall
    windows[windowId] = window
    return windowId
  }

  func attachMainWindow(window: NSWindow, _ channel: WindowChannel) {
    let mainWindow = BaseFlutterWindow(window: window, channel: channel)
    mainWindow.windowChannel.methodHandler = self.handleMethodCall
    windows[0] = mainWindow
  }

  private func handleMethodCall(
    fromWindowId: Int64, targetWindowId: Int64, method: String, arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let window = self.windows[targetWindowId] else {
      result(
        FlutterError(
          code: "-1", message: "failed to find target window. \(targetWindowId)", details: nil))
      return
    }
    window.windowChannel.invokeMethod(
      fromWindowId: fromWindowId, method: method, arguments: arguments, result: result)
  }

  func show(windowId: Int64) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.show()
  }

  func hide(windowId: Int64) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.hide()
  }

  func close(windowId: Int64) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.close()
  }

  func closeAll() {
    windows.forEach { _, value in
      value.close()
    }
  }

  func center(windowId: Int64) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.center()
  }

  func setFrame(windowId: Int64, frame: NSRect) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setFrame(frame: frame)
  }

  func getFrame(windowId: Int64) -> NSDictionary {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      let data: NSDictionary = [
        "x": 0,
        "y": 0,
        "width": 0,
        "height": 0,
      ]
      return data
    }
    let frameRect: NSRect = window.window.frame

    let data: NSDictionary = [
      "x": frameRect.topLeft.x,
      "y": frameRect.topLeft.y,
      "width": frameRect.size.width,
      "height": frameRect.size.height,
    ]
    return data
  }

  func setTitle(windowId: Int64, title: String) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setTitle(title: title)
  }

  func resizable(windowId: Int64, resizable: Bool) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.resizable(resizable: resizable)
  }

  func setFrameAutosaveName(windowId: Int64, name: String) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setFrameAutosaveName(name: name)
  }

  func getAllSubWindowIds() -> [Int64] {
    return windows.keys.filter { $0 != 0 }
  }
}

protocol WindowManagerDelegate: AnyObject {
  func onClose(windowId: Int64)
}

extension MultiWindowManager: WindowManagerDelegate {
  func onClose(windowId: Int64) {
    windows.removeValue(forKey: windowId)
  }
}
