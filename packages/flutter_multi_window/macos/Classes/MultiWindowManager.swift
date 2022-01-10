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

  func create() -> Int64 {
    id += 1
    let windowId = id

    let window = FlutterWindow(id: windowId)
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
    windows.removeValue(forKey: windowId)
  }

  func closeAll() {
    windows.forEach { (key, value) in
      value.close()
    }
    windows.removeAll()
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

}

protocol WindowManagerDelegate: AnyObject {
  func onClose(windowId: Int64)

  func onFocus(windowId: Int64)

  func onResize(windowId: Int64, width: Int, height: Int)

  func onMove(windowId: Int64, x: Int, y: Int)

  func onMinimize(windowId: Int64)

  func onMaximize(windowId: Int64)

  func onRestore(windowId: Int64)

  func onFullscreen(windowId: Int64)

  func onUnfullscreen(windowId: Int64)

  func onShow(windowId: Int64)

  func onHide(windowId: Int64)
}
