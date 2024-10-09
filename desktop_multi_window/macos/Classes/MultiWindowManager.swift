//
//  MultiWindowManager.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//

import FlutterMacOS
import Foundation

class MultiWindowManager {
  static let shared = MultiWindowManager()

  private var id: Int64 = 0

  private var windows: [Int64: BaseFlutterWindow] = [:]

  func create(arguments: String) -> Int64 {
    id += 1
    let windowId = id

    let window = FlutterWindow(id: windowId, arguments: arguments)
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

  private func handleMethodCall(fromWindowId: Int64, targetWindowId: Int64, method: String, arguments: Any?, result: @escaping FlutterResult) {
    guard let window = self.windows[targetWindowId] else {
      result(FlutterError(code: "-1", message: "failed to find target window. \(targetWindowId)", details: nil))
      return
    }
    window.windowChannel.invokeMethod(fromWindowId: fromWindowId, method: method, arguments: arguments, result: result)
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
