import Cocoa
import FlutterMacOS

/// Tracks browser views on the application-owned engine.
final class TitleBarViews {
  enum StartupError: Error {
    case multiViewUnavailable
    case mainViewNotConfigured
  }

  private struct Registration {
    weak var controller: FlutterViewController?
    let webViewId: Int64
    let titleBarTopPadding: Int
  }

  private weak var engine: FlutterEngine?
  private var engineId: Int64?
  private var mainViewId: Int64?
  private static let mainControllers = NSMapTable<AnyObject, FlutterViewController>.weakToWeakObjects()
  private let channel: FlutterMethodChannel
  private var registrations: [Int64: Registration] = [:]
  private var isShutdown = false

  // Flutter 3.47.6 has these selectors, but does not expose them in its public
  // headers. Keep this compatibility boundary here, and fail creation clearly
  // if a future engine removes them. Do not fall back to per-window engines.
  private static let enableMultiViewSelector = NSSelectorFromString("enableMultiView")
  private static let removeViewControllerSelector = NSSelectorFromString("removeViewController:")

  init(messenger: FlutterBinaryMessenger) {
    if let controller = Self.mainControllers.object(forKey: messenger as AnyObject) {
      engine = controller.engine
      mainViewId = controller.viewIdentifier
      engineId = Int64(Int(bitPattern: Unmanaged.passUnretained(controller.engine).toOpaque()))
    }
    channel = FlutterMethodChannel(
      name: "desktop_webview_window/titlebars", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, !self.isShutdown else {
        result(FlutterError(code: "titlebar_views_closed", message: "The titlebar view registry is closed", details: nil))
        return
      }
      switch call.method {
      case "initialize":
        guard self.engine != nil, let mainViewId = self.mainViewId else {
          result(FlutterError(code: "titlebar_multiview_unavailable", message: "Create the main controller with DesktopWebviewWindowPlugin.createMainViewController() before registering plugins", details: nil))
          return
        }
        result(mainViewId)
      case "getViews":
        result(self.snapshot())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

  }

  // This is called by the runner before constructing its first controller.
  static func createMainViewController() throws -> FlutterViewController {
    let engine = FlutterEngine(
      name: "desktop_webview_window.app", project: FlutterDartProject(),
      allowHeadlessExecution: true)
    guard engine.responds(to: enableMultiViewSelector),
          engine.responds(to: removeViewControllerSelector) else {
      throw StartupError.multiViewUnavailable
    }
    typealias EnableMultiView = @convention(c) (AnyObject, Selector) -> Void
    let enable = unsafeBitCast(engine.method(for: enableMultiViewSelector), to: EnableMultiView.self)
    enable(engine, enableMultiViewSelector)
    guard engine.run(withEntrypoint: nil) else {
      throw StartupError.mainViewNotConfigured
    }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    mainControllers.setObject(controller, forKey: engine.binaryMessenger as AnyObject)
    return controller
  }

  func createView(webViewId: Int64, titleBarTopPadding: Int) -> FlutterViewController {
    precondition(!isShutdown)
    guard let engine = engine else { preconditionFailure("Application engine is unavailable") }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    registrations[controller.viewIdentifier] = Registration(
      controller: controller, webViewId: webViewId,
      titleBarTopPadding: titleBarTopPadding)
    #if DEBUG
    print("TITLEBAR_VIEW add engine=\(ObjectIdentifier(engine)) view=\(controller.viewIdentifier) browser=\(webViewId) count=\(registrations.count)")
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
    print("TITLEBAR_VIEW remove engine=\(engineId ?? 0) view=\(viewId) count=\(registrations.count)")
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
    guard let engine = engine else { return }
    typealias RemoveViewController = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    let removeViewController = unsafeBitCast(
      engine.method(for: Self.removeViewControllerSelector), to: RemoveViewController.self)
    removeViewController(engine, Self.removeViewControllerSelector, controller)
  }

  #if DEBUG
  func debugState() -> [String: Any] {
    ["engine": engineId as Any, "mainViewId": mainViewId as Any, "views": snapshot()]
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
  }

  deinit {
    shutdown()
  }
}
