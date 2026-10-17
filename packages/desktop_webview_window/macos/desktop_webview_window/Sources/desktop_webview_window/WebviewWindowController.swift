//
//  WebviewWindowController.swift
//  webview_window
//
//  Created by Bin Yang on 2021/10/15.
//

import Cocoa
import FlutterMacOS
import WebKit

// Borderless browser windows must still accept keyboard input.
private class BrowserWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

class WebviewWindowController: NSWindowController {
  private let methodChannel: FlutterMethodChannel

  private let viewId: Int64

  let webViewController: WebViewLayoutController

  private var isClosed = false

  private var isDestroyed = false

  public weak var webviewPlugin: DesktopWebviewWindowPlugin?

  init(viewId: Int64, methodChannel: FlutterMethodChannel,
       width: Int, height: Int,
       title: String, showSystemTitleBar: Bool, titleBarHeight: Int,
       titleBarController: FlutterViewController?,
       titleBarViews: TitleBarViews?) {
    self.viewId = viewId
    self.methodChannel = methodChannel
    webViewController = WebViewLayoutController(
      methodChannel: methodChannel, viewId: viewId,
      titleBarHeight: titleBarHeight,
      titleBarController: titleBarController, titleBarViews: titleBarViews)
    super.init(window: nil)

    var styleMask: NSWindow.StyleMask = showSystemTitleBar
      ? [.titled, .closable, .miniaturizable, .resizable]
      : [.borderless, .resizable]
    let usesFlutterTitlebar = showSystemTitleBar && titleBarController != nil
    if usesFlutterTitlebar {
      styleMask.insert(.fullSizeContentView)
    }
    let newWindow = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                  styleMask: styleMask, backing: .buffered, defer: false)
    newWindow.delegate = self
    newWindow.title = title
    newWindow.titlebarAppearsTransparent = usesFlutterTitlebar

    newWindow.contentViewController = webViewController
    newWindow.setContentSize(NSSize(width: width, height: height))
    newWindow.center()

    window = newWindow
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func close() {
    guard !isClosed, !isDestroyed else { return }
    super.close()
    // Ensure programmatic close completes even if AppKit did not send the
    // delegate callback (for example, when the window was never shown).
    finishClose()
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == "w" && event.modifierFlags.contains(.command) {
      close()
    }
  }

  func destroy(closeWindow: Bool = true) {
    guard !isDestroyed else { return }
    isDestroyed = true
    webViewController.destroy()
    webviewPlugin = nil
    window?.delegate = nil
    window?.contentViewController = nil
    if closeWindow {
      window?.close()
    }
    window = nil
  }

  private func finishClose() {
    guard !isClosed, !isDestroyed else { return }
    isClosed = true
    // Remove the browser first: detaching a Flutter view can pump platform
    // messages, which must no longer be able to operate on this window.
    webviewPlugin?.onWebviewWindowClose(viewId: viewId, wc: self)
    destroy(closeWindow: false)
    methodChannel.invokeMethod("onWindowClose", arguments: ["id": viewId])
  }

  func setAppearance(brightness: Int) {
    switch brightness {
    case 0:
      if #available(macOS 10.14, *) {
        window?.appearance = NSAppearance(named: .darkAqua)
      } else {
        // Fallback on earlier versions
      }
      break
    case 1:
      window?.appearance = NSAppearance(named: .aqua)
      break
    default:
      window?.appearance = nil
      break
    }
  }

  deinit {
    #if DEBUG
      print("\(self) deinited")
    #endif
  }
}

extension WebviewWindowController: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    finishClose()
  }
}
