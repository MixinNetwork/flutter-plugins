//
//  MultiWindowManager.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//

import Foundation

class MultiWindowManager {
  static let shared = MultiWindowManager()

  private var id: Int64 = 1

  private var windows: [Int64: FlutterWindow] = [:]

  private var windowPlugins: [Int64: FlutterWindow] = [:]

  func create(arguments: String) -> Int64 {
    id += 1
    let windowId = id

    let window = FlutterWindow(id: windowId, arguments: arguments)
    window.delegate = self
    windows[windowId] = window
    return windowId
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

  func setSize(windowId: Int64, width: Int, height: Int) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setSize(width: width, height: height)
  }

  func setPosition(windowId: Int64, x: Int, y: Int) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setPosition(x: x, y: y)
  }

  func setTitle(windowId: Int64, title: String) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setTitle(title: title)
  }

  func setFrameAutosaveName(windowId: Int64, name: String) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setFrameAutosaveName(name: name)
  }

  func startDragging(windowId: Int64) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.startDragging()
  }

  func setMinSize(windowId: Int64, width: Int, height: Int) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setMinSize(width: width, height: height)
  }

  func setMaxSize(windowId: Int64, width: Int, height: Int) {
    guard let window = windows[windowId] else {
      debugPrint("window \(windowId) not exists.")
      return
    }
    window.setMaxSize(width: width, height: height)
  }

}

protocol WindowManagerDelegate: AnyObject {
  func onClose(windowId: Int64)
}

extension MultiWindowManager: WindowManagerDelegate {
  func onClose(windowId: Int64) {
    debugPrint("close : \(windowId)")
    windows.removeValue(forKey: windowId)
  }
}
