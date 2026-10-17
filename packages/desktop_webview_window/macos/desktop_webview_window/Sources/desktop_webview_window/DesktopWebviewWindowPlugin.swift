import Cocoa
import FlutterMacOS
import WebKit
#if SWIFT_PACKAGE
// Runners install composers through `import desktop_webview_window`.
@_exported import desktop_webview_window_composer
#endif

public class DesktopWebviewWindowPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel

  private var webviews: [Int64: WebviewWindowController] = [:]

  private var isDetached = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    DefaultComposer.install()
    let channel = FlutterMethodChannel(
      name: "desktop_webview_window", binaryMessenger: registrar.messenger)
    let instance = DesktopWebviewWindowPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    teardown()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !isDetached else {
      result(FlutterError(code: "engine_detached", message: "The plugin was detached", details: nil))
      return
    }
    let argument = call.arguments as? [String: Any?] ?? [:]
    switch call.method {
    case "isWebviewAvailable":
      result(true)
      return
    case "create":
      create(argument, result: result)
      return
    case "clearAll":
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast,
        completionHandler: { result(nil) })
      return
    default:
      break
    }

    guard let viewId = argument["viewId"] as? Int64 else {
      result(FlutterError(code: "invalid_argument", message: "viewId is required", details: nil))
      return
    }
    if call.method == "close" {
      // A duplicated or delayed close is already satisfied.
      webviews[viewId]?.requestClose()
      result(nil)
      return
    }
    guard let wc = webviews[viewId] else {
      result(FlutterError(code: "browser_closed", message: "No open browser with id \(viewId)", details: nil))
      return
    }
    let webView = wc.webViewController
    switch call.method {
    case "launch":
      guard let url = argument["url"] as? String, let parsed = URL(string: url) else {
        result(FlutterError(code: "invalid_argument", message: "Invalid url", details: nil))
        return
      }
      let decide = argument["triggerOnUrlRequestEvent"] as? Bool ?? true
      webView.load(url: parsed, decide: decide)
      result(nil)
    case "setUrlRequestEnabled":
      webView.urlRequestEnabled = argument["enabled"] as? Bool ?? false
      result(nil)
    case "postJavaScriptMessage":
      guard let script = argument["script"] as? String else {
        result(FlutterError(code: "invalid_argument", message: "script is required", details: nil))
        return
      }
      webView.evaluate(script) { _, error in
        result(error.map {
          FlutterError(code: "javascript_error", message: $0.localizedDescription, details: nil)
        })
      }
    case "setBrightness":
      wc.setAppearance(brightness: argument["brightness"] as? Int ?? -1)
      result(nil)
    case "addScriptToExecuteOnDocumentCreated":
      guard let javaScript = argument["javaScript"] as? String else {
        result(FlutterError(code: "invalid_argument", message: "javaScript is required", details: nil))
        return
      }
      webView.addScriptToExecuteOnDocumentCreated(javaScript: javaScript)
      result(nil)
    case "setApplicationNameForUserAgent":
      guard let applicationName = argument["applicationName"] as? String else {
        result(FlutterError(code: "invalid_argument", message: "applicationName is required", details: nil))
        return
      }
      webView.setApplicationNameForUserAgent(applicationName: applicationName)
      result(nil)
    case "back":
      webView.goBack()
      result(nil)
    case "forward":
      webView.goForward()
      result(nil)
    case "reload":
      webView.reload()
      result(nil)
    case "stop":
      webView.stopLoading()
      result(nil)
    case "evaluateJavaScript":
      guard let js = argument["javaScriptString"] as? String else {
        result(FlutterError(code: "invalid_argument", message: "javaScriptString is required", details: nil))
        return
      }
      webView.evaluateJavaScript(javaScriptString: js, completer: result)
    case "getAllCookies":
      webView.getAllCookies(completer: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func create(_ argument: [String: Any?], result: @escaping FlutterResult) {
    let viewId = dww_darwin_next_browser_id()
    let options = WebviewWindowController.Options(
      width: argument["windowWidth"] as? Int ?? 1280,
      height: argument["windowHeight"] as? Int ?? 720,
      x: argument["windowPosX"] as? Int ?? 0,
      y: argument["windowPosY"] as? Int ?? 0,
      usePosition: argument["useWindowPositionAndSize"] as? Bool ?? false,
      title: argument["title"] as? String ?? "",
      showSystemTitleBar: argument["showSystemTitleBar"] as? Bool ?? true,
      showToolbar: argument["showToolbar"] as? Bool ?? true,
      composerArguments: argument["composerArguments"] as? String,
      javaScriptBridge: argument["javaScriptBridge"] as? String)
    let controller = WebviewWindowController(viewId: viewId, channel: channel, options: options)
    controller.onClosed = { [weak self] wc in
      guard let self = self, self.webviews[wc.viewId] === wc else { return }
      self.webviews.removeValue(forKey: wc.viewId)
    }
    webviews[viewId] = controller
    controller.start(
      options: options,
      openMaximized: argument["openMaximized"] as? Bool ?? false,
      openHidden: argument["openHidden"] as? Bool ?? false)
    if controller.isClosing {
      // Closed from a composer callback: tear down before replying, so Dart
      // receives a browser that has already closed.
      controller.destroyNow()
      result(["id": viewId, "windowHandle": 0, "closed": true])
      return
    }
    let handle = controller.window.map { Int64(Int(bitPattern: Unmanaged.passUnretained($0).toOpaque())) } ?? 0
    result(["id": viewId, "windowHandle": handle])
  }

  private func teardown() {
    guard !isDetached else { return }
    isDetached = true
    for controller in webviews.values {
      controller.detach()
    }
    webviews.removeAll()
  }

  deinit {
    teardown()
  }
}
