//
//  WebViewLayoutController.swift
//  desktop_webView_window
//
//  Created by Bin Yang on 2021/11/18.
//

import Cocoa
import FlutterMacOS
import WebKit

class WebViewLayoutController: NSViewController {
  private var titleBarController: FlutterViewController?

  private weak var titleBarEngine: SharedTitleBarEngine?

  private lazy var webView: WKWebView = {
    WKWebView()
  }()

  private var javaScriptHandlerNames: [String] = []

  private var observesNavigation = false

  private var isDestroyed = false

  private var defaultUserAgent: String?

  private let methodChannel: FlutterMethodChannel

  private let viewId: Int64

  private let titleBarHeight: Int

  init(methodChannel: FlutterMethodChannel, viewId: Int64, titleBarHeight: Int,
       titleBarController: FlutterViewController?, titleBarEngine: SharedTitleBarEngine?) {
    self.viewId = viewId
    self.methodChannel = methodChannel
    self.titleBarHeight = titleBarHeight
    self.titleBarController = titleBarController
    self.titleBarEngine = titleBarEngine
    #if SWIFT_PACKAGE
    // SwiftPM places resources in a per-module bundle exposed as `Bundle.module`.
    super.init(nibName: "WebViewLayoutController", bundle: Bundle.module)
    #else
    // CocoaPods build: the nib is in the framework bundle of this class.
    super.init(nibName: "WebViewLayoutController", bundle: Bundle(for: WebViewLayoutController.self))
    #endif
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    super.loadView()
    guard !isDestroyed else { return }

    var webViewTopAnchor = view.topAnchor
    if let titleBarController = titleBarController {
      addChild(titleBarController)
      let flutterView = titleBarController.view
      flutterView.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(flutterView)
      NSLayoutConstraint.activate([
        flutterView.topAnchor.constraint(equalTo: view.topAnchor),
        flutterView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        flutterView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        flutterView.heightAnchor.constraint(equalToConstant: CGFloat(titleBarHeight)),
      ])
      webViewTopAnchor = flutterView.bottomAnchor
    }

    // WKWebView occupies its own native rectangle. Flutter only owns the optional
    // titlebar above it; a toolbar-less window reserves no Flutter layout space.
    view.addSubview(webView)
    webView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: webViewTopAnchor),
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    guard !isDestroyed else { return }

    webView.navigationDelegate = self
    webView.uiDelegate = self

    // TODO(boyan01) Make it configuable from flutter.
    webView.configuration.preferences.javaEnabled = true
    webView.configuration.preferences.minimumFontSize = 12
    webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    webView.configuration.allowsAirPlayForMediaPlayback = true
    webView.configuration.mediaTypesRequiringUserActionForPlayback = .video

    webView.addObserver(self, forKeyPath: "canGoBack", options: .new, context: nil)
    webView.addObserver(self, forKeyPath: "canGoForward", options: .new, context: nil)
    webView.addObserver(self, forKeyPath: "loading", options: .new, context: nil)
    observesNavigation = true

    defaultUserAgent = webView.value(forKey: "userAgent") as? String
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard !isDestroyed else { return }
    if keyPath == "canGoBack" || keyPath == "canGoForward" {
      methodChannel.invokeMethod("onHistoryChanged", arguments: [
        "id": viewId,
        "canGoBack": webView.canGoBack,
        "canGoForward": webView.canGoForward,
      ] as [String: Any])
    } else if keyPath == "loading" {
      if webView.isLoading {
        methodChannel.invokeMethod("onNavigationStarted", arguments: [
          "id": viewId,
        ])
      } else {
        methodChannel.invokeMethod("onNavigationCompleted", arguments: [
          "id": viewId,
        ])
      }
    }
  }

  func load(url: URL) {
    debugPrint("load url: \(url)")
    webView.load(URLRequest(url: url))
  }

  func addJavascriptInterface(name: String) {
    javaScriptHandlerNames.append(name)
    webView.configuration.userContentController.add(self, name: name)
  }

  func removeJavascriptInterface(name: String) {
    if let index = javaScriptHandlerNames.firstIndex(of: name) {
      javaScriptHandlerNames.remove(at: index)
    }
    webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
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
      if observesNavigation {
        webView.removeObserver(self, forKeyPath: "canGoBack")
        webView.removeObserver(self, forKeyPath: "canGoForward")
        webView.removeObserver(self, forKeyPath: "loading")
        observesNavigation = false
      }
      webView.navigationDelegate = nil
      webView.uiDelegate = nil
      for name in javaScriptHandlerNames {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
      }
      javaScriptHandlerNames.removeAll()
      webView.stopLoading()
      webView.removeFromSuperview()
    }
    if let titleBarController = titleBarController {
      if titleBarController.isViewLoaded {
        titleBarController.view.removeFromSuperview()
      }
      titleBarController.removeFromParent()
      titleBarEngine?.removeView(titleBarController)
    }
    titleBarController = nil
    titleBarEngine = nil
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
      completer(result)
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
          "expiresDate": cookie.expiresDate?.timeIntervalSince1970 ?? NSNull(),
          "isSecure": cookie.isSecure,
          "isHTTPOnly": cookie.isHTTPOnly,
          "isSessionOnly": cookie.isSessionOnly,
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
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }

    guard ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else {
      decisionHandler(.cancel)
      return
    }

    methodChannel.invokeMethod("onUrlRequested", arguments: [
      "id": viewId,
      "url": url.absoluteString,
    ] as [String: Any])

    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    decisionHandler(.allow)
  }
}

extension WebViewLayoutController: WKUIDelegate {
  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    methodChannel.invokeMethod(
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
    methodChannel.invokeMethod(
      "onJavaScriptMessage",
      arguments: [
        "id": viewId,
        "name": message.name,
        "body": message.body,
      ])
  }
}
