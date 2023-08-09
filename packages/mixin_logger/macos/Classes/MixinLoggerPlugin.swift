import Cocoa
import FlutterMacOS

public class MixinLoggerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    MixinLoggerWriteLog(nil)
    MixinLoggerInit(nil, 0, 0, nil)
  }
}
