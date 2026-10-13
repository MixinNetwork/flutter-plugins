import Cocoa
import FlutterMacOS
import WebKit

// Browser IDs remain process-wide because the message bridge spans engines.
private var nextWebViewId: Int64 = 0

public class DesktopWebviewWindowPlugin: NSObject, FlutterPlugin {
  private let methodChannel: FlutterMethodChannel

  private var webviews: [Int64: WebviewWindowController] = [:]

  private var titleBarEngine: SharedTitleBarEngine?

  public init(methodChannel: FlutterMethodChannel) {
    self.methodChannel = methodChannel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "webview_window", binaryMessenger: registrar.messenger)
    let instance = DesktopWebviewWindowPlugin(methodChannel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    ClientMessageChannelPlugin.register(with: registrar)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    #if DEBUG
    case "debugTitleBarState":
      result(titleBarEngine?.debugState() ?? ["views": []])
      return
    #endif
    case "create":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      let width = argument["windowWidth"] as? Int ?? 1280
      let height = argument["windowHeight"] as? Int ?? 720
      let title = argument["title"] as? String ?? ""
      let titleBarHeight = argument["titleBarHeight"] as? Int ?? 50
      let titleBarTopPadding = max(0, argument["titleBarTopPadding"] as? Int ?? 0)
      let useTitleBar = argument["useTitleBar"] as? Bool ?? true
      let viewId = nextWebViewId
      nextWebViewId += 1

      var titleBarController: FlutterViewController?
      if useTitleBar && titleBarHeight > 0 {
        do {
          if titleBarEngine == nil {
            titleBarEngine = try SharedTitleBarEngine()
          }
          titleBarController = titleBarEngine?.createView(
            webViewId: viewId, titleBarTopPadding: titleBarTopPadding)
        } catch SharedTitleBarEngine.StartupError.multiViewUnavailable {
          result(FlutterError(
            code: "titlebar_multiview_unavailable",
            message: "Shared titlebars require Flutter 3.47.6 or a compatible macOS engine with multi-view support",
            details: nil))
          return
        } catch {
          result(FlutterError(
            code: "titlebar_engine_start_failed", message: "Could not start the shared titlebar engine",
            details: nil))
          return
        }
      }

      let controller = WebviewWindowController(
        viewId: viewId, methodChannel: methodChannel,
        width: width, height: height, title: title,
        titleBarHeight: titleBarController == nil ? 0 : titleBarHeight + titleBarTopPadding,
        titleBarController: titleBarController, titleBarEngine: titleBarEngine
      )
      controller.webviewPlugin = self
      webviews[viewId] = controller
      controller.showWindow(nil)
      result(viewId)
      break
    case "launch":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }

      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }

      guard let url = argument["url"] as? String else {
        result(FlutterError(code: "0", message: "param url not found", details: nil))
        return
      }

      guard let parsedUrl = URL(string: url) else {
        result(FlutterError(code: "0", message: "failed to parse \(url)", details: nil))
        return
      }

      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.load(url: parsedUrl)
      result(nil)
      break
    case "registerJavaScriptInterface":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let name = argument["name"] as? String else {
        result(FlutterError(code: "0", message: "param name not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.addJavascriptInterface(name: name)
      result(nil)
      break
    case "unregisterJavaScriptInterface":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let name = argument["name"] as? String else {
        result(FlutterError(code: "0", message: "param name not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.removeJavascriptInterface(name: name)
      result(nil)
      break
    case "clearAll":
      WKWebsiteDataStore.default().removeData(
        ofTypes: [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage],
        modifiedSince: .distantPast,
        completionHandler: {
          result(nil)
        })
      break
    case "setBrightness":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      let brightness = argument["brightness"] as? Int ?? -1
      wc.setAppearance(brightness: brightness)
      result(nil)
      break
    case "addScriptToExecuteOnDocumentCreated":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      guard let javaScript = argument["javaScript"] as? String else {
        result(FlutterError(code: "0", message: "param javaScript not found", details: nil))
        return
      }
      wc.webViewController.addScriptToExecuteOnDocumentCreated(javaScript: javaScript)
      result(nil)
      break
    case "setApplicationNameForUserAgent":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      guard let applicationName = argument["applicationName"] as? String else {
        result(FlutterError(code: "0", message: "param applicationName not found", details: nil))
        return
      }
      wc.webViewController.setApplicationNameForUserAgent(applicationName: applicationName)
      result(nil)
      break
    case "back":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.goBack()
      break
    case "forward":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.goForward()
      break
    case "reload":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.reload()
      break
    case "stop":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.stopLoading()
      break
    case "close":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        // Closing an already closed window is harmless, including a duplicate
        // request while a native close event is being delivered.
        result(nil)
        return
      }
      wc.close()
      result(nil)
      break
    case "evaluateJavaScript":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      guard let js = argument["javaScriptString"] as? String else {
        result(FlutterError(code: "0", message: "param javaScriptString not found", details: nil))
        return
      }
      wc.webViewController.evaluateJavaScript(javaScriptString: js, completer: result)
      break
    case "getAllCookies":
      guard let argument = call.arguments as? [String: Any?] else {
        result(FlutterError(code: "0", message: "arg is not map", details: nil))
        return
      }
      guard let viewId = argument["viewId"] as? Int64 else {
        result(FlutterError(code: "0", message: "param viewId not found", details: nil))
        return
      }
      guard let wc = webviews[viewId] else {
        result(FlutterError(code: "0", message: "can not find webview for id: \(viewId)", details: nil))
        return
      }
      wc.webViewController.getAllCookies(completer: result)
      break
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onWebviewWindowClose(viewId: Int64, wc: WebviewWindowController) {
    guard webviews[viewId] === wc else { return }
    webviews.removeValue(forKey: viewId)
  }

  deinit {
    // Controllers must detach before the one shared engine shuts down.
    for controller in webviews.values {
      controller.destroy()
    }
    webviews.removeAll()
    titleBarEngine?.shutdown()
  }
}
