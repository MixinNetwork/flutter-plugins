//
//  FlutterWindow.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//
import Cocoa
import FlutterMacOS
import Foundation

class BaseFlutterWindow: NSObject {
  let window: NSWindow
  let windowChannel: WindowChannel

  init(window: NSWindow, channel: WindowChannel) {
    self.window = window
    self.windowChannel = channel
    super.init()
  }

  public func show() {
    window.setIsVisible(true)
    DispatchQueue.main.async {
      self.window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  public func hide() {
    DispatchQueue.main.async {
      self.window.orderOut(nil)
    }
  }

  func center() {
    window.center()
  }

  func setFrame(frame: NSRect) {
    window.setFrame(frame, display: false, animate: true)
  }

  func setTitle(title: String) {
    window.title = title
  }

  func resizable(resizable: Bool) {
    if resizable {
      window.styleMask.insert(.resizable)
    } else {
      window.styleMask.remove(.resizable)
    }
  }

  func close() {
    window.close()
  }

  func setFrameAutosaveName(name: String) {
    window.setFrameAutosaveName(name)
  }
}

class FlutterWindow: BaseFlutterWindow {
  let windowId: Int64

  weak var delegate: WindowManagerDelegate?

  init(id: Int64, arguments: String, windowOptions: WindowOptions) {
    windowId = id

    let createdWindow: NSWindow

    let contentRect: NSRect = NSRect(
      x: windowOptions.x, y: windowOptions.y, width: windowOptions.width,
      height: windowOptions.height)

    if windowOptions.type == "NSPanel" {
      createdWindow = NSPanel(
        contentRect: contentRect,
        styleMask: NSWindow.StyleMask(rawValue: windowOptions.styleMask),
        // styleMask: [.nonactivatingPanel, .utilityWindow],
        backing: .buffered, defer: false)
    } else {
      createdWindow = NSWindow(
        contentRect: contentRect,
        // styleMask: NSWindow.StyleMask(rawValue: windowOptions.styleMask),
        styleMask: [.miniaturizable, .closable, .resizable, .titled, .fullSizeContentView],
        backing: .buffered, defer: false)
    }

    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["multi_window", "\(windowId)", arguments]
    let flutterViewController = FlutterViewController(project: project)
    createdWindow.contentViewController = flutterViewController

    let plugin = flutterViewController.registrar(forPlugin: "FlutterMultiWindowPlugin")
    FlutterMultiWindowPlugin.registerInternal(with: plugin)
    let windowChannel = WindowChannel.register(with: plugin, windowId: id)
    // Give app a chance to register plugin.
    FlutterMultiWindowPlugin.onWindowCreatedCallback?(flutterViewController)

    super.init(window: createdWindow, channel: windowChannel)
    createdWindow.delegate = self

    createdWindow.isReleasedWhenClosed = false
    createdWindow.titleVisibility = .hidden
    createdWindow.titlebarAppearsTransparent = true

    createdWindow.title = windowOptions.title
    createdWindow.isOpaque = windowOptions.isOpaque
    createdWindow.hasShadow = windowOptions.hasShadow
    createdWindow.isMovable = windowOptions.isMovable
    createdWindow.backgroundColor = windowOptions.backgroundColor
    flutterViewController.backgroundColor = windowOptions.backgroundColor
    createdWindow.standardWindowButton(.closeButton)?.isHidden = !windowOptions
      .windowButtonVisibility
    createdWindow.standardWindowButton(.miniaturizeButton)?.isHidden = !windowOptions
      .windowButtonVisibility
    createdWindow.standardWindowButton(.zoomButton)?.isHidden = !windowOptions
      .windowButtonVisibility
    createdWindow.level = NSWindow.Level(rawValue: windowOptions.level)
    // window.backingType = windowOptions.backing == "buffered" ? .buffered : .retained
    // window.collectionBehavior = NSWindow.CollectionBehavior(rawValue: windowOptions.collectionBehavior ?? 0)
    createdWindow.ignoresMouseEvents = windowOptions.ignoresMouseEvents ?? false
    // window.acceptsMouseMovedEvents = windowOptions.acceptsMouseMovedEvents ?? false
    // window.animationBehavior = NSWindow.AnimationBehavior(rawValue: windowOptions.animationBehavior ?? 0)

    let frameRect = NSWindow.frameRect(
      forContentRect: contentRect, styleMask: createdWindow.styleMask)
    createdWindow.setFrame(frameRect, display: true)
    NSApplication.shared.setActivationPolicy(.accessory);
  }

  deinit {
    debugPrint("release window resource")
    window.delegate = nil
    if let flutterViewController = window.contentViewController as? FlutterViewController {
      flutterViewController.engine.shutDownEngine()
    }
    window.contentViewController = nil
    window.windowController = nil
  }
}

extension FlutterWindow: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    delegate?.onClose(windowId: windowId)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    delegate?.onClose(windowId: windowId)
    return true
  }
}
