import Cocoa
import FlutterMacOS

/// Owns the one titlebar isolate. Windows own their controllers, never the engine.
final class SharedTitleBarEngine {
  enum StartupError: Error {
    case multiViewUnavailable
    case engineRunFailed
  }

  private struct Registration {
    weak var controller: FlutterViewController?
    let webViewId: Int64
    let titleBarTopPadding: Int
  }

  private let engine: FlutterEngine
  private let channel: FlutterMethodChannel
  private var registrations: [Int64: Registration] = [:]
  private var isShutdown = false

  // Flutter 3.47.6 has these selectors, but does not expose them in its public
  // headers. Keep this compatibility boundary here, and fail creation clearly
  // if a future engine removes them. Do not fall back to per-window engines.
  private static let enableMultiViewSelector = NSSelectorFromString("enableMultiView")
  private static let removeViewControllerSelector = NSSelectorFromString("removeViewController:")

  init() throws {
    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["web_view_title_bar", "shared"]
    engine = FlutterEngine(
      name: "desktop_webview_window.titlebars",
      project: project,
      allowHeadlessExecution: true)
    channel = FlutterMethodChannel(
      name: "desktop_webview_window/titlebars",
      binaryMessenger: engine.binaryMessenger)

    guard engine.responds(to: Self.enableMultiViewSelector),
          engine.responds(to: Self.removeViewControllerSelector) else {
      throw StartupError.multiViewUnavailable
    }

    // Multi-view must be enabled before the first controller is constructed.
    // A typed IMP is used because these Objective-C methods return void.
    typealias EnableMultiView = @convention(c) (AnyObject, Selector) -> Void
    let enableMultiView = unsafeBitCast(
      engine.method(for: Self.enableMultiViewSelector), to: EnableMultiView.self)
    enableMultiView(engine, Self.enableMultiViewSelector)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, !self.isShutdown else {
        result(FlutterError(code: "titlebar_engine_closed", message: "The titlebar engine is closed", details: nil))
        return
      }
      switch call.method {
      case "getViews":
        result(self.snapshot())
      case "ready":
        result(nil)
        self.viewsChanged()
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Register the broadcast bridge once for the isolate, not once per view.
    ClientMessageChannelPlugin.register(
      with: engine.registrar(forPlugin: "DesktopWebviewWindowTitleBarMessages"))

    // FlutterViewController.init immediately calls AddView. That requires a
    // running engine even when the first view has not loaded yet.
    guard engine.run(withEntrypoint: nil) else {
      throw StartupError.engineRunFailed
    }
  }

  func createView(webViewId: Int64, titleBarTopPadding: Int) -> FlutterViewController {
    precondition(!isShutdown)
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    registrations[controller.viewIdentifier] = Registration(
      controller: controller, webViewId: webViewId,
      titleBarTopPadding: titleBarTopPadding)
    #if DEBUG
    print("TITLEBAR_ENGINE add engine=\(ObjectIdentifier(engine)) view=\(controller.viewIdentifier) browser=\(webViewId) count=\(registrations.count)")
    #endif
    viewsChanged()
    return controller
  }

  func removeView(_ controller: FlutterViewController) {
    guard !isShutdown,
          let viewId = registrations.first(where: { $0.value.controller === controller })?.key else {
      return
    }
    registrations.removeValue(forKey: viewId)
    #if DEBUG
    print("TITLEBAR_ENGINE remove engine=\(ObjectIdentifier(engine)) view=\(viewId) count=\(registrations.count)")
    #endif
    // Remove the mapping before detaching. RemoveView may pump platform messages,
    // and Dart must not rebuild a titlebar for a window that is already closing.
    viewsChanged()
    detach(controller)
  }

  private func snapshot() -> [[String: Any]] {
    registrations.keys.sorted().compactMap { viewId in
      guard let registration = registrations[viewId], registration.controller != nil else {
        return nil
      }
      return [
        "viewId": viewId,
        "webViewId": registration.webViewId,
        "titleBarTopPadding": registration.titleBarTopPadding,
      ]
    }
  }

  private func viewsChanged() {
    channel.invokeMethod("viewsChanged", arguments: nil)
  }

  private func detach(_ controller: FlutterViewController) {
    typealias RemoveViewController = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    let removeViewController = unsafeBitCast(
      engine.method(for: Self.removeViewControllerSelector), to: RemoveViewController.self)
    removeViewController(engine, Self.removeViewControllerSelector, controller)
  }

  #if DEBUG
  func debugState() -> [String: Any] {
    ["engine": String(describing: ObjectIdentifier(engine)), "views": snapshot()]
  }
  #endif

  func shutdown() {
    guard !isShutdown else { return }
    isShutdown = true
    channel.setMethodCallHandler(nil)
    let controllers = registrations.values.compactMap { $0.controller }
    registrations.removeAll()
    for controller in controllers {
      detach(controller)
    }
    engine.shutDownEngine()
  }

  deinit {
    shutdown()
  }
}
