//
//  WebviewWindowController.swift
//  webview_window
//
//  Created by Bin Yang on 2021/10/15.
//

import Cocoa
import FlutterMacOS
import WebKit
#if SWIFT_PACKAGE
import desktop_webview_window_composer
#endif

// Borderless browser windows must still accept keyboard input.
private class BrowserWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class WebviewWindowController: NSWindowController {
  struct Options {
    let width: Int
    let height: Int
    let x: Int
    let y: Int
    let usePosition: Bool
    let title: String
    let showSystemTitleBar: Bool
    let showToolbar: Bool
    let composerArguments: String?
    let javaScriptBridge: String?
  }

  private let channel: FlutterMethodChannel

  let viewId: Int64

  let webViewController: WebViewLayoutController

  private let composer = dww_darwin_binding_new()!

  private(set) var isClosing = false

  private var isClosed = false

  private var published: NavigationState?

  /// Called once the window has closed, before Dart is told.
  var onClosed: ((WebviewWindowController) -> Void)?

  init(viewId: Int64, channel: FlutterMethodChannel, options: Options) {
    self.viewId = viewId
    self.channel = channel
    webViewController = WebViewLayoutController(
      channel: channel, viewId: viewId, javaScriptBridge: options.javaScriptBridge)
    super.init(window: nil)

    let styleMask: NSWindow.StyleMask = options.showSystemTitleBar
      ? [.titled, .closable, .miniaturizable, .resizable]
      : [.borderless, .resizable]
    let newWindow = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: options.width, height: options.height),
                                  styleMask: styleMask, backing: .buffered, defer: false)
    newWindow.delegate = self
    newWindow.title = options.title
    // The controller owns the window; AppKit must not release it on close.
    newWindow.isReleasedWhenClosed = false
    // An empty root for the composer.
    newWindow.contentView = NSView()
    newWindow.setContentSize(NSSize(width: options.width, height: options.height))
    if options.usePosition, let screen = NSScreen.screens.first {
      // Dart positions are top-left based; AppKit's origin is bottom-left.
      let top = screen.frame.maxY - CGFloat(options.y)
      newWindow.setFrameTopLeftPoint(NSPoint(x: CGFloat(options.x), y: top))
    } else {
      newWindow.center()
    }
    window = newWindow
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Composes, publishes the initial navigation state and shows the window.
  /// A close requested meanwhile skips the rest; finish it with destroyNow().
  func start(options: Options, openMaximized: Bool, openHidden: Bool) {
    guard let window = window else { return }
    register()
    let container = webViewController.view
    webViewController.onNavigationStateChanged = { [weak self] state in
      self?.publish(state)
    }
    withComposeRequest(options: options, window: window, container: container) { request in
      dww_darwin_binding_compose(composer, request)
    }
    if isClosing { return }
    if container.superview == nil, let root = window.contentView {
      fill(root, with: container)
    }
    publish(webViewController.navigationState)
    if isClosing { return }
    if openMaximized {
      window.zoom(nil)
    }
    if !openHidden {
      showWindow(nil)
    }
  }

  private func withComposeRequest(options: Options, window: NSWindow, container: NSView,
                                  _ body: (UnsafePointer<DWWComposeRequest>) -> Void) {
    let windowPointer = Unmanaged.passUnretained(window).toOpaque()
    let viewPointer = Unmanaged.passUnretained(container).toOpaque()
    func make(_ arguments: UnsafePointer<CChar>?) {
      var request = DWWComposeRequest(
        browser: viewId, window: windowPointer, webview_view: viewPointer,
        arguments: arguments, show_toolbar: options.showToolbar ? 1 : 0)
      body(&request)
    }
    if let arguments = options.composerArguments {
      arguments.withCString { make($0) }
    } else {
      make(nil)
    }
  }

  private func fill(_ root: NSView, with view: NSView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: root.topAnchor),
      view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
    ])
  }

  private func publish(_ state: NavigationState) {
    guard !isClosing, state != published else { return }
    published = state
    channel.invokeMethod("onNavigationStateChanged", arguments: [
      "id": viewId,
      "canGoBack": state.canGoBack,
      "canGoForward": state.canGoForward,
      "isLoading": state.isLoading,
      "url": state.url as Any,
      "title": state.title as Any,
    ] as [String: Any])
    withCStrings(state.url, state.title) { url, title in
      var native = DWWNavigationState(
        browser: viewId, can_go_back: state.canGoBack ? 1 : 0,
        can_go_forward: state.canGoForward ? 1 : 0, is_loading: state.isLoading ? 1 : 0,
        url: url, title: title)
      dww_darwin_binding_navigation_changed(composer, &native)
    }
  }

  private func withCStrings(_ first: String?, _ second: String?,
                            _ body: (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void) {
    func with(_ value: String?, _ inner: (UnsafePointer<CChar>?) -> Void) {
      if let value = value { value.withCString { inner($0) } } else { inner(nil) }
    }
    with(first) { a in with(second) { b in body(a, b) } }
  }

  // MARK: Browser control, reached through dww_browser_*.

  private func register() {
    var ops = DWWDarwinBrowser(
      target: Unmanaged.passUnretained(self).toOpaque(),
      go_back: { WebviewWindowController.from($0).control { $0.webViewController.goBack() } },
      go_forward: { WebviewWindowController.from($0).control { $0.webViewController.goForward() } },
      reload: { WebviewWindowController.from($0).control { $0.webViewController.reload() } },
      stop: { WebviewWindowController.from($0).control { $0.webViewController.stopLoading() } },
      close: { WebviewWindowController.from($0).requestClose() ? 1 : 0 })
    dww_darwin_register_browser(viewId, &ops)
  }

  private static func from(_ target: UnsafeMutableRawPointer?) -> WebviewWindowController {
    Unmanaged<WebviewWindowController>.fromOpaque(target!).takeUnretainedValue()
  }

  private func control(_ action: (WebviewWindowController) -> Void) -> Int32 {
    guard !isClosing else { return 0 }
    action(self)
    return 1
  }

  /// Requests closing. Inside a composer callback it takes effect afterwards.
  @discardableResult
  func requestClose() -> Bool {
    guard !isClosing, !isClosed else { return false }
    isClosing = true
    dww_darwin_binding_begin_close(composer)
    if dww_darwin_binding_dispatching(composer) != 0 {
      // Composer code is on the stack; tear down once it has returned.
      DispatchQueue.main.async { [self] in destroyNow() }
      return true
    }
    destroyNow()
    return true
  }

  override func close() {
    requestClose()
  }

  /// Tears the window down now. Only valid outside composer callbacks.
  func destroyNow() {
    guard !isClosed else { return }
    isClosing = true
    isClosed = true
    dww_darwin_binding_begin_close(composer)
    dww_darwin_binding_closing(composer, viewId)
    dww_darwin_unregister_browser(viewId)
    webViewController.destroy()
    if let window = window {
      window.delegate = nil
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    window = nil
    onClosed?(self)
    onClosed = nil
    channel.invokeMethod("onWindowClose", arguments: ["id": viewId])
  }

  /// Engine teardown: release the window without notifying Dart.
  func detach() {
    onClosed = nil
    guard !isClosed else { return }
    isClosing = true
    isClosed = true
    dww_darwin_binding_begin_close(composer)
    dww_darwin_binding_closing(composer, viewId)
    dww_darwin_unregister_browser(viewId)
    webViewController.destroy()
    window?.delegate = nil
    window?.close()
    window = nil
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == "w" && event.modifierFlags.contains(.command) {
      requestClose()
    }
  }

  func setAppearance(brightness: Int) {
    switch brightness {
    case 0:
      if #available(macOS 10.14, *) {
        window?.appearance = NSAppearance(named: .darkAqua)
      }
    case 1:
      window?.appearance = NSAppearance(named: .aqua)
    default:
      window?.appearance = nil
    }
  }

  deinit {
    dww_darwin_binding_free(composer)
    #if DEBUG
      print("\(self) deinited")
    #endif
  }
}

extension WebviewWindowController: NSWindowDelegate {
  // The close button takes the same path as every other close request.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    requestClose()
    return false
  }
}
