import Cocoa
import FlutterMacOS
import WebKit
import desktop_webview_window

/// An example native composer. "sidebar" stacks the controls left of the page;
/// "close:<callback>" closes the browser from that callback for the
/// integration suite. Other browsers use the plugin's default composer.
enum TestComposer {
  private static var handled: [Int64: String] = [:]
  // "<browser>:<callback>" in delivery order.
  private static var events: [String] = []

  private static func record(_ browser: Int64, _ event: String) {
    events.append("\(browser):\(event)")
  }

  static func install() {
    var composer = DWWComposer(
      user: nil,
      compose: { _, request in TestComposer.compose(request!.pointee) },
      navigation_changed: { _, state in TestComposer.navigationChanged(state!.pointee) },
      layout: nil,
      closing: { _, browser in TestComposer.closing(browser) })
    dww_set_composer(&composer)
  }

  private static func compose(_ request: DWWComposeRequest) -> DWWComposeResult {
    record(request.browser, "compose")
    guard let arguments = request.arguments else { return DWW_COMPOSE_DEFAULT }
    let mode = String(cString: arguments)
    handled[request.browser] = mode
    if mode == "close:compose" {
      record(request.browser, dww_browser_close(request.browser) != 0 ? "close-accepted" : "close-ignored")
      return DWW_COMPOSE_HANDLED
    }
    if mode == "sidebar" {
      let window = Unmanaged<NSWindow>.fromOpaque(request.window).takeUnretainedValue()
      let webView = Unmanaged<NSView>.fromOpaque(request.webview_view).takeUnretainedValue()
      let browser = request.browser
      let column = NSStackView(views: [
        ControlButton(NSImage.goLeftTemplateName) { dww_browser_go_back(browser) },
        ControlButton(NSImage.goRightTemplateName) { dww_browser_go_forward(browser) },
        ControlButton(NSImage.refreshTemplateName) { dww_browser_reload(browser) },
      ])
      column.orientation = .vertical
      column.alignment = .centerX
      column.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
      let row = NSStackView(views: [column, webView])
      row.orientation = .horizontal
      row.spacing = 0
      row.alignment = .top
      row.distribution = .fill
      row.translatesAutoresizingMaskIntoConstraints = false
      let root = window.contentView!
      root.addSubview(row)
      NSLayoutConstraint.activate([
        column.widthAnchor.constraint(equalToConstant: 48),
        column.heightAnchor.constraint(equalTo: row.heightAnchor),
        webView.heightAnchor.constraint(equalTo: row.heightAnchor),
        row.topAnchor.constraint(equalTo: root.topAnchor),
        row.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        row.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        row.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      ])
    }
    // Other modes leave webview_view unplaced; it then fills the window.
    return DWW_COMPOSE_HANDLED
  }

  private static func navigationChanged(_ state: DWWNavigationState) {
    record(state.browser, "navigation")
    // Close once a page has finished loading.
    if handled[state.browser] == "close:navigation", state.url != nil, state.is_loading == 0 {
      record(state.browser, dww_browser_close(state.browser) != 0 ? "close-accepted" : "close-ignored")
    }
  }

  private static func closing(_ browser: Int64) {
    record(browser, "closing")
    if handled[browser] == "close:closing" {
      record(browser, dww_browser_close(browser) != 0 ? "close-accepted" : "close-ignored")
    }
    handled[browser] = nil
  }

  private final class ControlButton: NSButton {
    private let handler: () -> Void

    init(_ image: NSImage.Name, handler: @escaping () -> Void) {
      self.handler = handler
      super.init(frame: .zero)
      self.image = NSImage(named: image)
      isBordered = false
      target = self
      action = #selector(run)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() { handler() }
  }

  // MARK: Integration-suite channel

  private static func descendants<T: NSView>(of view: NSView, _ type: T.Type) -> [T] {
    var found: [T] = []
    if let match = view as? T { found.append(match) }
    for child in view.subviews { found += descendants(of: child, type) }
    return found
  }

  /// Title bar items, then buttons in the content view.
  private static func buttons(of window: NSWindow, content: NSView) -> [() -> Void] {
    let items = (window.toolbar?.items ?? []).filter { $0.action != nil }
    return items.map { item in { NSApp.sendAction(item.action!, to: item.target, from: item) } }
      + descendants(of: content, NSButton.self).map { button in { button.performClick(nil) } }
  }

  static func registerChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "webview_example/native_test", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "composerEvents":
        result(events)
        return
      case "clearComposerEvents":
        events.removeAll()
        result(nil)
        return
      default:
        break
      }
      guard let handle = args["handle"] as? Int64, handle != 0,
            let raw = UnsafeRawPointer(bitPattern: Int(handle)) else {
        result(FlutterError(code: "no_window", message: "Unknown window", details: nil))
        return
      }
      let window = Unmanaged<NSWindow>.fromOpaque(raw).takeUnretainedValue()
      guard let content = window.contentView else {
        result(FlutterError(code: "no_window", message: "Unknown window", details: nil))
        return
      }
      content.layoutSubtreeIfNeeded()
      switch call.method {
      case "webviewPixel", "startupPixel":
        guard let webView = descendants(of: content, WKWebView.self).first else {
          result(FlutterError(code: "no_webview", message: "No WebView", details: nil))
          return
        }
        func pixel(_ image: NSBitmapImageRep?) {
          guard let image = image,
                let color = image.colorAt(x: image.pixelsWide / 2, y: image.pixelsHigh / 2)?
                  .usingColorSpace(.deviceRGB) else {
            result(FlutterError(code: "no_snapshot", message: "No rendered image", details: nil))
            return
          }
          result([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent])
        }
        if call.method == "startupPixel", let container = webView.superview {
          let image = container.bitmapImageRepForCachingDisplay(in: container.bounds)
          if let image = image { container.cacheDisplay(in: container.bounds, to: image) }
          pixel(image)
        } else {
          webView.takeSnapshot(with: nil) { image, _ in
            pixel(image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
              .map { NSBitmapImageRep(cgImage: $0) })
          }
        }
      case "geometry":
        guard let webView = descendants(of: content, WKWebView.self).first else {
          result(FlutterError(code: "no_webview", message: "No WebView", details: nil))
          return
        }
        let frame = webView.convert(webView.bounds, to: content)
        let top = content.isFlipped ? frame.minY : content.bounds.height - frame.maxY
        result([
          "contentWidth": Int(content.bounds.width.rounded()),
          "contentHeight": Int(content.bounds.height.rounded()),
          "webX": Int(frame.minX.rounded()),
          "webY": Int(top.rounded()),
          "webWidth": Int(frame.width.rounded()),
          "webHeight": Int(frame.height.rounded()),
          "buttons": buttons(of: window, content: content).count,
        ])
      case "resize":
        let width = args["width"] as? Int ?? 0
        let height = args["height"] as? Int ?? 0
        window.setContentSize(NSSize(width: width, height: height))
        result(nil)
      case "windowTitle":
        result(window.title)
      case "sheet":
        // The page dialog or panel attached to the window, if any.
        guard let sheet = window.attachedSheet else {
          result(nil)
          return
        }
        let buttons = sheet.contentView.map { descendants(of: $0, NSButton.self) } ?? []
        result([
          "kind": sheet is NSSavePanel ? "panel" : "alert",
          "buttons": buttons.map { $0.title }.filter { !$0.isEmpty },
        ])
      case "endSheet":
        // Ends the attached sheet as if the alert button at index was
        // clicked. Panels end as cancelled.
        guard let sheet = window.attachedSheet else {
          result(FlutterError(code: "no_sheet", message: "No sheet", details: nil))
          return
        }
        let index = args["index"] as? Int ?? 0
        window.endSheet(
          sheet,
          returnCode: sheet is NSSavePanel
            ? .cancel
            : NSApplication.ModalResponse(
              rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index))
        result(nil)
      case "clickButton":
        let buttons = buttons(of: window, content: content)
        let index = args["index"] as? Int ?? -1
        guard buttons.indices.contains(index) else {
          result(FlutterError(code: "no_button", message: "No such button", details: nil))
          return
        }
        buttons[index]()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
