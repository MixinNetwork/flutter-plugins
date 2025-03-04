//
//  FlutterWindow.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//
import Cocoa
import FlutterMacOS
import Foundation

extension NSWindow {
  private struct AssociatedKeys {
    static var configured: Bool = false
  }
  var configured: Bool {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.configured) as? Bool ?? false
    }
    set(value) {
      objc_setAssociatedObject(
        self, &AssociatedKeys.configured, value,
        objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
  public func hiddenWindowAtLaunch() {
    if !configured {
      setIsVisible(false)
      configured = true
    }
  }
}

// Protocol for handling window events
protocol WindowEventHandler: AnyObject {
  func handleWindowWillClose()
  func handleWindowShouldClose() -> Bool
  func handleWindowShouldZoom() -> Bool
  func handleWindowDidResize()
  func handleWindowDidEndLiveResize()
  func handleWindowWillMove()
  func handleWindowDidMove()
  func handleWindowDidBecomeKey()
  func handleWindowDidResignKey()
  func handleWindowDidBecomeMain()
  func handleWindowDidResignMain()
  func handleWindowDidMiniaturize()
  func handleWindowDidDeminiaturize()
  func handleWindowDidEnterFullScreen()
  func handleWindowDidExitFullScreen()
}

// Proxy class that forwards delegate calls
class WindowDelegateProxy: NSObject, NSWindowDelegate {
  weak var originalDelegate: NSWindowDelegate?
  weak var eventHandler: WindowEventHandler?

  public func windowWillClose(_ notification: Notification) {
    eventHandler?.handleWindowWillClose()
    originalDelegate?.windowWillClose?(notification)
  }

  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    let shouldClose = eventHandler?.handleWindowShouldClose() ?? true
    return originalDelegate?.windowShouldClose?(sender) ?? shouldClose
  }

  public func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
    let shouldZoom = eventHandler?.handleWindowShouldZoom() ?? true
    return originalDelegate?.windowShouldZoom?(window, toFrame: newFrame) ?? shouldZoom
  }

  public func windowDidResize(_ notification: Notification) {
    eventHandler?.handleWindowDidResize()
    originalDelegate?.windowDidResize?(notification)
  }

  public func windowDidEndLiveResize(_ notification: Notification) {
    eventHandler?.handleWindowDidEndLiveResize()
    originalDelegate?.windowDidEndLiveResize?(notification)
  }

  public func windowWillMove(_ notification: Notification) {
    eventHandler?.handleWindowWillMove()
    originalDelegate?.windowWillMove?(notification)
  }

  public func windowDidMove(_ notification: Notification) {
    eventHandler?.handleWindowDidMove()
    originalDelegate?.windowDidMove?(notification)
  }

  public func windowDidBecomeKey(_ notification: Notification) {
    eventHandler?.handleWindowDidBecomeKey()
    originalDelegate?.windowDidBecomeKey?(notification)
  }

  public func windowDidResignKey(_ notification: Notification) {
    eventHandler?.handleWindowDidResignKey()
    originalDelegate?.windowDidResignKey?(notification)
  }

  public func windowDidBecomeMain(_ notification: Notification) {
    eventHandler?.handleWindowDidBecomeMain()
    originalDelegate?.windowDidBecomeMain?(notification)
  }

  public func windowDidResignMain(_ notification: Notification) {
    eventHandler?.handleWindowDidResignMain()
    originalDelegate?.windowDidResignMain?(notification)
  }

  public func windowDidMiniaturize(_ notification: Notification) {
    eventHandler?.handleWindowDidMiniaturize()
    originalDelegate?.windowDidMiniaturize?(notification)
  }

  public func windowDidDeminiaturize(_ notification: Notification) {
    eventHandler?.handleWindowDidDeminiaturize()
    originalDelegate?.windowDidDeminiaturize?(notification)
  }

  public func windowDidEnterFullScreen(_ notification: Notification) {
    eventHandler?.handleWindowDidEnterFullScreen()
    originalDelegate?.windowDidEnterFullScreen?(notification)
  }

  public func windowDidExitFullScreen(_ notification: Notification) {
    eventHandler?.handleWindowDidExitFullScreen()
    originalDelegate?.windowDidExitFullScreen?(notification)
  }

  // Forward any unhandled messages to the original delegate
  override func responds(to aSelector: Selector!) -> Bool {
    return super.responds(to: aSelector) || originalDelegate?.responds(to: aSelector) == true
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    if originalDelegate?.responds(to: aSelector) == true {
      return originalDelegate
    }
    return super.forwardingTarget(for: aSelector)
  }
}

class BaseFlutterWindow: NSObject {
  let windowId: Int64
  let window: NSWindow
  let interWindowEventChannel: InterWindowEventChannel
  let windowEventsChannel: WindowEventsChannel
  weak var delegate: WindowManagerDelegate?

  private var _isPreventClose: Bool = false
  private var _isMaximized: Bool = false
  private var _isMaximizable: Bool = true

  private weak var originalDelegate: NSWindowDelegate?
  private let delegateProxy: WindowDelegateProxy
  private var delegateObservation: NSKeyValueObservation?

  init(
    id: Int64, window: NSWindow, interWindowEventChannel: InterWindowEventChannel,
    windowEventsChannel: WindowEventsChannel
  ) {
    self.windowId = id
    self.window = window
    self.interWindowEventChannel = interWindowEventChannel
    self.windowEventsChannel = windowEventsChannel

    self.originalDelegate = window.delegate
    self.delegateProxy = WindowDelegateProxy()

    super.init()

    self.windowEventsChannel.methodHandler = handleMethodCall

    // Set up the proxy
    self.delegateProxy.originalDelegate = self.originalDelegate
    self.delegateProxy.eventHandler = self
    self.window.delegate = self.delegateProxy

    // Observe delegate changes
    self.delegateObservation = window.observe(\.delegate, options: [.new, .old]) {
      [weak self] window, change in
      guard let self = self else { return }
      if let newDelegate = change.newValue as? NSWindowDelegate,
        newDelegate !== self.delegateProxy
      {
        self.originalDelegate = newDelegate
        self.delegateProxy.originalDelegate = newDelegate
        window.delegate = self.delegateProxy
      }
    }
  }

  private func emitEvent(_ eventName: String) {
    let args: NSDictionary = [
      "eventName": eventName
    ]
    windowEventsChannel.methodChannel.invokeMethod("onEvent", arguments: args, result: nil)
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

  public func isFocused() -> Bool {
    return window.isKeyWindow
  }

  public func focus() {
    NSApp.activate(ignoringOtherApps: false)
    window.makeKeyAndOrderFront(nil)
  }

  func center() {
    window.center()
  }

  func getFrame() -> NSRect {
    return window.frame
  }

  func setFrame(frame: NSRect, animate: Bool) {
    if animate {
      window.animator().setFrame(frame, display: true, animate: true)
    } else {
      window.setFrame(frame, display: true)
    }
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

  public func isMinimized() -> Bool {
    return window.isMiniaturized
  }

  public func maximize() {
    if !isMaximized() {
      window.zoom(nil)
    }
  }

  public func unmaximize() {
    if isMaximized() {
      window.zoom(nil)
    }
  }

  public func minimize() {
    window.miniaturize(nil)
  }

  public func restore() {
    window.deminiaturize(nil)
  }

  public func isFullScreen() -> Bool {
    return window.styleMask.contains(.fullScreen)
  }

  public func setFullScreen(isFullScreen: Bool) {
    if isFullScreen {
      if !window.styleMask.contains(.fullScreen) {
        window.toggleFullScreen(nil)
      }
    } else {
      if window.styleMask.contains(.fullScreen) {
        window.toggleFullScreen(nil)
      }
    }
  }

  public func isMaximized() -> Bool {
    return window.isZoomed
  }

  public func isVisible() -> Bool {
    return window.isVisible
  }

  public func isPreventClose() -> Bool {
    return _isPreventClose
  }

  public func isMaximizable() -> Bool {
    return _isMaximizable
  }

  func setFrameAutosaveName(name: String) {
    window.setFrameAutosaveName(name)
  }

  func handleMethodCall(
    method: String, arguments: [String: Any?]?, result: @escaping FlutterResult
  ) {
    switch method {
    case "show":
      show()
      result(nil)
    case "hide":
      hide()
      result(nil)
    case "close":
      close()
      result(nil)
    case "center":
      center()
      result(nil)
    case "getFrame":
      let frameRect = getFrame()
      let data: NSDictionary = [
        "left": frameRect.topLeft.x,
        "top": frameRect.topLeft.y,
        "width": frameRect.size.width,
        "height": frameRect.size.height,
      ]
      result(data)
    case "setFrame":
      guard let arguments = arguments else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Arguments must be a dictionary",
            details: nil
          ))
        return
      }
      let animate = arguments["animate"] as? Bool ?? false

      var frameRect = getFrame()
      if arguments["width"] != nil && arguments["height"] != nil {
        let width: CGFloat = CGFloat(truncating: arguments["width"] as! NSNumber)
        let height: CGFloat = CGFloat(truncating: arguments["height"] as! NSNumber)

        frameRect.origin.y += (frameRect.size.height - height)
        frameRect.size.width = width
        frameRect.size.height = height
      }
      if arguments["left"] != nil && arguments["top"] != nil {
        frameRect.topLeft.x = CGFloat(truncating: arguments["left"] as! NSNumber)
        frameRect.topLeft.y = CGFloat(truncating: arguments["top"] as! NSNumber)
      }
      setFrame(frame: frameRect, animate: animate)
      result(nil)
    case "setTitle":
      guard let arguments = arguments else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Arguments must be a dictionary",
            details: nil
          ))
        return
      }
      let title = arguments["title"] as! String
      setTitle(title: title)
      result(nil)
    case "resizable":
      guard let arguments = arguments else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Arguments must be a dictionary",
            details: nil
          ))
        return
      }
      let value = arguments["resizable"] as! Bool
      resizable(resizable: value)
      result(nil)
    case "setFrameAutosaveName":
      guard let arguments = arguments else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Arguments must be a dictionary",
            details: nil
          ))
        return
      }
      let frameAutosaveName = arguments["name"] as! String
      setFrameAutosaveName(name: frameAutosaveName)
      result(nil)
    case "isFocused":
      let isFocused = isFocused()
      result(isFocused)
    case "isFullScreen":
      let isFullScreen = isFullScreen()
      result(isFullScreen)
    case "isMaximized":
      let isMaximized = isMaximized()
      result(isMaximized)
    case "isMinimized":
      let isMinimized = isMinimized()
      result(isMinimized)
    case "isVisible":
      let isVisible = isVisible()
      result(isVisible)
    case "maximize":
      maximize()
      result(nil)
    case "unmaximize":
      unmaximize()
      result(nil)
    case "minimize":
      minimize()
      result(nil)
    case "restore":
      restore()
      result(nil)
    case "setFullScreen":
      let isFullScreen = arguments?["isFullScreen"] as? Bool ?? false
      setFullScreen(isFullScreen: isFullScreen)
      result(nil)
    case "setWindowStyle":
      let styleMask = arguments?["styleMask"] as? UInt
      let collectionBehavior = arguments?["collectionBehavior"] as? UInt
      let level = arguments?["level"] as? Int
      let isOpaque = arguments?["isOpaque"] as? Bool ?? true
      let hasShadow = arguments?["hasShadow"] as? Bool ?? true
      if let bgColor = arguments?["backgroundColor"] as? [String: Any] {
        let backgroundColor =
          WindowOptions.parseColor(from: bgColor) ?? NSColor.windowBackgroundColor
        (window.contentViewController as? FlutterViewController)?.backgroundColor = backgroundColor
        window.backgroundColor = backgroundColor
      } else {
        // ToDo: This might be wrong??
        window.backgroundColor = NSColor.windowBackgroundColor
        (window.contentViewController as? FlutterViewController)?.backgroundColor = NSColor.windowBackgroundColor
      }
      window.styleMask = NSWindow.StyleMask(rawValue: styleMask ?? 0)
      window.collectionBehavior = NSWindow.CollectionBehavior(rawValue: collectionBehavior ?? 0)
      window.level = NSWindow.Level(rawValue: level ?? 0)
      window.isOpaque = isOpaque
      window.hasShadow = hasShadow
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  deinit {
    debugPrint("Releasing window resources")
    delegateObservation?.invalidate()
    if window.delegate === delegateProxy {
      window.delegate = originalDelegate
    }
    if let flutterViewController = window.contentViewController as? FlutterViewController {
      DispatchQueue.main.async {
        flutterViewController.engine.shutDownEngine()
      }
    }
    window.contentViewController = nil
    window.windowController = nil
  }
}

// Implementation of event handling
extension BaseFlutterWindow: WindowEventHandler {
  func handleWindowWillClose() {
    delegate?.onClose(windowId: windowId)
  }

  func handleWindowShouldClose() -> Bool {
    emitEvent("close")
    if isPreventClose() {
      return false
    }
    delegate?.onClose(windowId: windowId)
    return true
  }

  func handleWindowShouldZoom() -> Bool {
    emitEvent("maximize")
    return isMaximizable()
  }

  func handleWindowDidResize() {
    emitEvent("resize")
    if !_isMaximized && window.isZoomed {
      _isMaximized = true
      emitEvent("maximize")
    }
    if _isMaximized && !window.isZoomed {
      _isMaximized = false
      emitEvent("unmaximize")
    }
  }

  func handleWindowDidEndLiveResize() {
    emitEvent("resized")
  }

  func handleWindowWillMove() {
    emitEvent("move")
  }

  func handleWindowDidMove() {
    emitEvent("moved")
  }

  func handleWindowDidBecomeKey() {
    if window is NSPanel {
      emitEvent("focus")
    }
  }

  func handleWindowDidResignKey() {
    if window is NSPanel {
      emitEvent("blur")
    }
  }

  func handleWindowDidBecomeMain() {
    emitEvent("focus")
  }

  func handleWindowDidResignMain() {
    emitEvent("blur")
  }

  func handleWindowDidMiniaturize() {
    emitEvent("minimize")
  }

  func handleWindowDidDeminiaturize() {
    emitEvent("restore")
  }

  func handleWindowDidEnterFullScreen() {
    emitEvent("enter-full-screen")
  }

  func handleWindowDidExitFullScreen() {
    emitEvent("leave-full-screen")
  }
}

class FlutterWindow: BaseFlutterWindow {

  init(id: Int64, arguments: String, windowOptions: WindowOptions) {

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
        styleMask: NSWindow.StyleMask(rawValue: windowOptions.styleMask),
        // styleMask: [.miniaturizable, .closable, .resizable, .titled, .fullSizeContentView],
        backing: .buffered, defer: false)
    }

    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["multi_window", "\(id)", arguments]
    let flutterViewController = FlutterViewController(project: project)
    createdWindow.contentViewController = flutterViewController

    let plugin = flutterViewController.registrar(forPlugin: "FlutterMultiWindowPlugin")
    FlutterMultiWindowPlugin.registerInternal(with: plugin)
    let interWindowEventChannel = InterWindowEventChannel.register(with: plugin, windowId: id)
    let windowEventsChannel = WindowEventsChannel.register(returns: plugin)

    // Give app a chance to register plugins.
    FlutterMultiWindowPlugin.onWindowCreatedCallback?(flutterViewController)

    super.init(
      id: id, window: createdWindow, interWindowEventChannel: interWindowEventChannel,
      windowEventsChannel: windowEventsChannel)

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
    NSApplication.shared.setActivationPolicy(.accessory)
  }
}
