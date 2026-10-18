//
//  WebViewLayoutController.swift
//  desktop_webView_window
//
//  Created by Bin Yang on 2021/11/18.
//

import Cocoa
import FlutterMacOS
import WebKit

/// Paints the fallback behind transparent WebKit content in the window's theme.
private final class WebViewBackground: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    dirtyRect.fill()
  }

  override func viewDidChangeEffectiveAppearance() {
    if #available(macOS 10.14, *) {
      super.viewDidChangeEffectiveAppearance()
    }
    needsDisplay = true
  }
}

/// Navigation state shared with Dart and the window's composer.
struct NavigationState: Equatable {
  var canGoBack = false
  var canGoForward = false
  var isLoading = false
  var url: String?
  var title: String?
}

/// Owns the WKWebView. Its view is the container handed to composers as
/// webview_view; the WebView itself and its delegates stay private.
class WebViewLayoutController: NSViewController {
  private lazy var webView: WKWebView = {
    let view = WKWebView()
    // WKWebView has no public macOS canvas setter; use WebKit's KVC switch.
    // underPageBackgroundColor alone does not remove the white page canvas.
    view.setValue(false, forKey: "drawsBackground")
    return view
  }()

  private static let bridgeHandlerName = "desktopWebview"

  private let javaScriptBridge: String?

  private var observesBridge = false

  // Set by launch(decide: false): the next main-frame navigation skips Dart.
  private var skipNextDecision = false

  private var observesNavigation = false

  private var isDestroyed = false

  // Only the first document needs a themed placeholder. Once WebKit has a
  // document, its normal canvas must respect that document's color-scheme.
  private var showsStartupBackground = true

  private var defaultUserAgent: String?

  private let channel: FlutterMethodChannel

  private let viewId: Int64

  /// Top-level navigations wait for Dart only while this is set.
  var urlRequestEnabled = false

  /// Called whenever the navigation state changes.
  var onNavigationStateChanged: ((NavigationState) -> Void)?

  private static let observedKeys = ["canGoBack", "canGoForward", "loading", "title", "URL"]

  init(channel: FlutterMethodChannel, viewId: Int64, javaScriptBridge: String?) {
    self.viewId = viewId
    self.channel = channel
    self.javaScriptBridge = javaScriptBridge
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let container = WebViewBackground()
    view = container
    guard !isDestroyed else { return }
    container.addSubview(webView)
    webView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: container.topAnchor),
      webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    guard !isDestroyed else { return }

    webView.navigationDelegate = self
    webView.uiDelegate = self

    // TODO(boyan01) Make it configuable from flutter.
    webView.configuration.preferences.minimumFontSize = 12
    webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    webView.configuration.allowsAirPlayForMediaPlayback = true
    webView.configuration.mediaTypesRequiringUserActionForPlayback = .video

    for key in Self.observedKeys {
      webView.addObserver(self, forKeyPath: key, options: .new, context: nil)
    }
    observesNavigation = true

    defaultUserAgent = webView.value(forKey: "userAgent") as? String

    if let bridge = javaScriptBridge {
      let controller = webView.configuration.userContentController
      controller.add(WeakScriptMessageHandler(self), name: Self.bridgeHandlerName)
      controller.addUserScript(
        WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
      observesBridge = true
    }
    #if DEBUG
    if #available(macOS 13.3, *) {
      webView.isInspectable = true
    }
    #endif
  }

  var navigationState: NavigationState {
    guard isViewLoaded, !isDestroyed else { return NavigationState() }
    return NavigationState(
      canGoBack: webView.canGoBack,
      canGoForward: webView.canGoForward,
      isLoading: webView.isLoading,
      url: webView.url?.absoluteString,
      title: webView.title.flatMap { $0.isEmpty ? nil : $0 })
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard !isDestroyed else { return }
    onNavigationStateChanged?(navigationState)
  }

  func load(url: URL, decide: Bool) {
    skipNextDecision = !decide
    webView.load(URLRequest(url: url))
  }

  func evaluate(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
    webView.evaluateJavaScript(script, completionHandler: completion)
  }

  func addScriptToExecuteOnDocumentCreated(javaScript: String) {
    webView.configuration.userContentController.addUserScript(
      WKUserScript(source: javaScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
  }

  func setApplicationNameForUserAgent(applicationName: String) {
    webView.customUserAgent = (defaultUserAgent ?? "") + applicationName
  }

  func destroy() {
    guard !isDestroyed else { return }
    isDestroyed = true
    // Do not force either lazy native view to load while closing an early window.
    if isViewLoaded {
      // Page dialogs and panels are sheets; ending them runs the completion
      // handlers WebKit is waiting for.
      if let window = view.window, let sheet = window.attachedSheet {
        window.endSheet(sheet)
      }
      if observesNavigation {
        for key in Self.observedKeys {
          webView.removeObserver(self, forKeyPath: key)
        }
        observesNavigation = false
      }
      webView.navigationDelegate = nil
      webView.uiDelegate = nil
      if observesBridge {
        webView.configuration.userContentController.removeScriptMessageHandler(
          forName: Self.bridgeHandlerName)
        observesBridge = false
      }
      webView.stopLoading()
      webView.removeFromSuperview()
    }
    onNavigationStateChanged = nil
  }

  func reload() {
    webView.reload()
  }

  func goBack() {
    if webView.canGoBack {
      webView.goBack()
    }
  }

  func goForward() {
    if webView.canGoForward {
      webView.goForward()
    }
  }

  func stopLoading() {
    webView.stopLoading()
  }

  func evaluateJavaScript(javaScriptString: String, completer: @escaping FlutterResult) {
    webView.evaluateJavaScript(javaScriptString) { result, error in
      if let error = error {
        completer(FlutterError(code: "1", message: error.localizedDescription, details: nil))
        return
      }
      // Results cross the bridge as JSON so every platform returns the same
      // shape. Undefined and null both become nil.
      guard let result = result, !(result is NSNull) else {
        completer(nil)
        return
      }
      let value = Self.jsonCompatible(result)
      guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
            let json = String(data: data, encoding: .utf8) else {
        completer(FlutterError(code: "javascript_result", message: "The result is not JSON-compatible", details: nil))
        return
      }
      completer(json)
    }
  }

  private static func jsonCompatible(_ value: Any) -> Any {
    switch value {
    case let date as Date:
      return date.timeIntervalSince1970 * 1000
    case let array as [Any]:
      return array.map(jsonCompatible)
    case let dictionary as [String: Any]:
      return dictionary.mapValues(jsonCompatible)
    default:
      return value
    }
  }

  func getAllCookies(completer: @escaping FlutterResult) {
    self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies{
      cookies in

      var cookieDict = [[String: Any]]()
      for cookie in cookies {
        cookieDict.append([
          "name": cookie.name,
          "value": cookie.value,
          "domain": cookie.domain,
          "path": cookie.path,
          "expires": cookie.expiresDate?.timeIntervalSince1970 ?? NSNull(),
          "secure": cookie.isSecure,
          "httpOnly": cookie.isHTTPOnly,
          "sessionOnly": cookie.isSessionOnly,
        ])
      }

      completer(cookieDict)
    }
  }

  deinit {
    #if DEBUG
      print("\(self) deinited")
    #endif
  }
}

extension WebViewLayoutController: WKNavigationDelegate {
  private func finishStartupBackground() {
    guard showsStartupBackground else { return }
    showsStartupBackground = false
    webView.setValue(true, forKey: "drawsBackground")
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    finishStartupBackground()
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    // A failure after commit still leaves a document. Provisional failures
    // and rejected navigations have no document and keep the placeholder.
    finishStartupBackground()
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }

    if #available(macOS 11.3, *), navigationAction.shouldPerformDownload {
      decisionHandler(.download)
      return
    }

    // WebKit cannot load other schemes, such as mixin: or mailto:. They still
    // reach Dart below so the application can handle them.
    let loadable = WKWebView.handlesURLScheme(url.scheme?.lowercased() ?? "")

    // Only top-level navigations are decided, as on the other platforms.
    guard navigationAction.targetFrame?.isMainFrame ?? true else {
      decisionHandler(loadable ? .allow : .cancel)
      return
    }
    if skipNextDecision {
      skipNextDecision = false
      decisionHandler(loadable ? .allow : .cancel)
      return
    }
    guard urlRequestEnabled else {
      decisionHandler(loadable ? .allow : .cancel)
      return
    }
    // The navigation waits for Dart. Anything but an explicit false allows it.
    channel.invokeMethod("onUrlRequest", arguments: [
      "id": viewId, "url": url.absoluteString,
    ] as [String: Any]) { result in
      decisionHandler((result as? Bool) == false || !loadable ? .cancel : .allow)
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if #available(macOS 11.3, *) {
      let disposition = (navigationResponse.response as? HTTPURLResponse)?
        .value(forHTTPHeaderField: "Content-Disposition")?.lowercased()
      if !navigationResponse.canShowMIMEType || disposition?.hasPrefix("attachment") == true {
        decisionHandler(.download)
        return
      }
    }
    decisionHandler(.allow)
  }

  @available(macOS 11.3, *)
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }

  @available(macOS 11.3, *)
  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    download.delegate = self
  }
}

/// Downloads ask where to save, as on Windows and Linux.
@available(macOS 11.3, *)
extension WebViewLayoutController: WKDownloadDelegate {
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    guard !isDestroyed, let window = view.window else {
      completionHandler(nil)
      return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedFilename
    panel.beginSheetModal(for: window) { result in
      guard result == .OK, let url = panel.url else {
        completionHandler(nil)
        return
      }
      // The panel has confirmed replacing an existing file; WKDownload
      // fails instead of overwriting it.
      try? FileManager.default.removeItem(at: url)
      completionHandler(url)
    }
  }
}

extension WebViewLayoutController: WKUIDelegate {
  // AppKit's own button titles, so dialogs follow the application's language.
  private static func appKitString(_ key: String) -> String {
    Bundle(for: NSApplication.self).localizedString(forKey: key, value: key, table: "Common")
  }

  /// Shows a page dialog as a sheet on the browser window. WebKit requires
  /// every completion handler to run: without a window the dialog answers
  /// false at once, and destroy() ends open sheets.
  private func showDialog(_ message: String, cancellable: Bool, completion: @escaping (Bool) -> Void) {
    guard !isDestroyed, let window = view.window else {
      completion(false)
      return
    }
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: Self.appKitString("OK"))
    if cancellable {
      alert.addButton(withTitle: Self.appKitString("Cancel"))
    }
    alert.beginSheetModal(for: window) { response in
      completion(response == .alertFirstButtonReturn)
    }
  }

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    showDialog(message, cancellable: false) { _ in completionHandler() }
  }

  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
    guard !isDestroyed, let window = view.window else {
      completionHandler(nil)
      return
    }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.beginSheetModal(for: window) { response in
      completionHandler(response == .OK ? panel.urls : nil)
    }
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    showDialog(message, cancellable: true, completion: completionHandler)
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    channel.invokeMethod(
      "runJavaScriptTextInputPanelWithPrompt",
      arguments: [
        "id": viewId,
        "prompt": prompt,
        "defaultText": defaultText ?? "",
      ] as [String: Any]) { result in
        completionHandler((result as? String) ?? "")
      }
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if !(navigationAction.targetFrame?.isMainFrame ?? false) {
      webView.load(navigationAction.request)
    }
    return nil
  }
}

extension WebViewLayoutController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard !isDestroyed, message.name == Self.bridgeHandlerName,
          message.frameInfo.isMainFrame,
          let body = message.body as? String else {
      return
    }
    channel.invokeMethod("onJavaScriptMessage", arguments: ["id": viewId, "message": body])
  }
}

/// WKUserContentController retains its handlers; this breaks the cycle with
/// the controller that owns the web view.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var target: WKScriptMessageHandler?

  init(_ target: WKScriptMessageHandler) {
    self.target = target
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
