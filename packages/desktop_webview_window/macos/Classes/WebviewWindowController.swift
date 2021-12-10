//
//  WebviewWindowController.swift
//  webview_window
//
//  Created by Bin Yang on 2021/10/15.
//

import Cocoa
import FlutterMacOS
import WebKit

class WebviewWindowController: NSWindowController {
  private let methodChannel: FlutterMethodChannel

  private let viewId: Int64

  private let width, height: Int

  private let titleBarHeight: Int
  
  private let titleBarTopPadding: Int
  
  private let title: String
  
  public weak var webviewPlugin: DesktopWebviewWindowPlugin?

  init(viewId: Int64, methodChannel: FlutterMethodChannel,
       width: Int, height: Int,
       title: String, titleBarHeight: Int,
       titleBarTopPadding: Int) {
    self.viewId = viewId
    self.methodChannel = methodChannel
    self.width = width
    self.height = height
    self.titleBarHeight = titleBarHeight
    self.titleBarTopPadding = titleBarTopPadding
    self.title = title
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public var webViewController: WebViewLayoutController {
    contentViewController as! WebViewLayoutController
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    contentViewController = WebViewLayoutController(
      methodChannel: methodChannel,
      viewId: viewId, titleBarHeight: titleBarHeight,
      titleBarTopPadding: titleBarTopPadding)

    window?.setContentSize(NSSize(width: width, height: height))
    window?.center()
    window?.title = title

    window?.isReleasedWhenClosed = false
    window?.delegate = self
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == "w" && event.modifierFlags.contains(.command) {
      close()
    }
  }

  func destroy() {
    window?.delegate = nil
    contentViewController = nil
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

  override var windowNibName: NSNib.Name? {
    "WebviewWindowController"
  }
}

extension WebviewWindowController: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    webViewController.destroy()
    methodChannel.invokeMethod("onWindowClose", arguments: ["id": viewId])
    DispatchQueue.main.async {
      self.webviewPlugin?.onWebviewWindowClose(viewId: self.viewId, wc: self)
    }
  }
}
