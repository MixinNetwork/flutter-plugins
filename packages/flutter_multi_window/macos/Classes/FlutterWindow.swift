//
//  FlutterWindow.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//
import Cocoa
import FlutterMacOS
import Foundation

class FlutterWindow {
  let windowId: Int64

  let window: NSWindow

  init(id: Int64) {
    windowId = id
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
      styleMask: [.miniaturizable, .closable, .resizable, .titled],
      backing: .buffered, defer: false)
    let flutterViewController = FlutterViewController()
    window.contentViewController = flutterViewController
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func hide() {
    window.orderOut(nil)
  }

  func center() {
    window.center()
  }

  func setSize(width: Int, height: Int) {
    window.setContentSize(NSSize(width: width, height: height))
  }

  func setPosition(x: Int, y: Int) {
    window.setFrameOrigin(NSPoint(x: x, y: y))
  }

  func setTitle(title: String) {
    window.title = title
  }

  func close() {
    window.close()
  }
  
}
