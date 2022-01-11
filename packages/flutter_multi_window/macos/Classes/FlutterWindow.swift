//
//  FlutterWindow.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//
import Cocoa
import FlutterMacOS
import Foundation

class FlutterWindow: NSObject {
  let windowId: Int64

  let window: NSWindow

  weak var delegate: WindowManagerDelegate?

  init(id: Int64, arguments: String) {
    windowId = id
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
      styleMask: [.miniaturizable, .closable, .resizable, .titled, .fullSizeContentView],
      backing: .buffered, defer: false)
    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["multi_window", "\(windowId)", arguments]
    let flutterViewController = FlutterViewController(project: project)
    window.contentViewController = flutterViewController

    FlutterMultiWindowPlugin.register(with: flutterViewController.registrar(forPlugin: "FlutterMultiWindowPlugin"))

    super.init()

    window.delegate = self
    window.isReleasedWhenClosed = false
    window.titleVisibility = .hidden
    
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

  func setFrameAutosaveName(name: String) {
    window.setFrameAutosaveName(name)
  }

}

extension FlutterWindow: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    window.delegate = nil
    window.contentViewController = nil
    window.windowController = nil
    delegate?.onClose(windowId: windowId)
  }
}
