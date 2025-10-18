import Cocoa
import FlutterMacOS

public class FlutterMultiWindowPlugin: NSObject, FlutterPlugin {
    
    private let window: FlutterWindow
    
    init(window: FlutterWindow) {
        self.window = window
        super.init()
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        guard let app = NSApplication.shared.delegate as? FlutterAppDelegate else {
            debugPrint(
                "failed to find flutter main window, application delegate is not FlutterAppDelegate")
            return
        }
        guard let window = app.mainFlutterWindow else {
            debugPrint("failed to find flutter main window")
            return
        }
        MultiWindowManager.shared.AttachWindow(window: window, registrar: registrar)
    }
    
    
    
    public typealias OnWindowCreatedCallback = (FlutterViewController) -> Void
    static var onWindowCreatedCallback: OnWindowCreatedCallback?
    
    public static func setOnWindowCreatedCallback(_ callback: @escaping OnWindowCreatedCallback) {
        onWindowCreatedCallback = callback
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let isWindowEvent = call.method.hasPrefix("window_")
        if isWindowEvent {
            let arguments = call.arguments as! [String: Any?]
            let windowId = arguments["windowId"] as! WindowId
            guard let window = MultiWindowManager.shared.windows[windowId] else {
                result(
                    FlutterError(
                        code: "-1", message: "failed to find target window. \(windowId)", details: nil))
                return
            }
            
            window.handleWindowMethod(method: call.method, arguments: arguments, result: result)
            return
        }
        
        switch call.method {
        case "createWindow":
            let arguments = call.arguments as? String
            let windowId = MultiWindowManager.shared.CreateWindow(arguments: arguments ?? "")
            result(windowId)
        case "getWindowDefinition":
            let definition: [String: Any] = [
                "windowId": window.windowId,
                "windowArgument": window.windowArgument,
            ]
            result(definition)
        default:
            result(FlutterMethodNotImplemented)
        }
        
    }
}

class MultiWindowManager :NSObject{
    
    static let shared: MultiWindowManager = MultiWindowManager()
    
    private  override init() {}
    
    var windows: [WindowId: FlutterWindow] = [:]
    
    func AttachWindow(window: NSWindow, registrar: FlutterPluginRegistrar) {
        // check window exists
        for (_, flutterWindow) in windows {
            if flutterWindow.window == window {
                return
            }
        }
        let windowId = WindowId.generate()
        let window = FlutterWindow(windowId: windowId, windowArgument: "", window: window)
        windows[windowId] = window
        registerMultiWindowChannel(window: window, with: registrar)
    }
    
    func CreateWindow(arguments: String) -> WindowId {
        let windowId = WindowId.generate()
        
        let config = WindowConfiguration.fromJson(arguments)
        
        debugPrint("Creating window with configuration: \(config)")
        
        let window = CustomWindow(configuration: config)
        
        let project = FlutterDartProject()
        project.dartEntrypointArguments = ["multi_window", windowId, config.arguments]
        let flutterViewController = FlutterViewController(project: project)
        window.contentViewController = flutterViewController

        window.orderFront(nil)
        window.setIsVisible(!config.hiddenAtLaunch)
        
        FlutterMultiWindowPlugin.onWindowCreatedCallback?(flutterViewController)
        
        let registrar = flutterViewController.registrar(forPlugin: "DesktopMultiWindowPlugin")
        
        let flutterWindow = FlutterWindow(windowId: windowId, windowArgument: config.arguments, window: window)
        windows[windowId] = flutterWindow
        registerMultiWindowChannel(window: flutterWindow, with: registrar)
        
        return windowId
    }
    
    // register multi window method channel for all engine. include main or created by this plugin
    private func registerMultiWindowChannel(window: FlutterWindow, with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "mixin.one/desktop_multi_window", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(FlutterMultiWindowPlugin(window: window), channel: channel)
    }
    
}
