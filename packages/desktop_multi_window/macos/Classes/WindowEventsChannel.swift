//
//  WindowEventsChannel.swift
//  desktop_multi_window
//
//  Created by Konstantin Wachendorff on 2025/03/01.
//

import FlutterMacOS
import Foundation

typealias WindowMethodHandler = (String, [String: Any?]?, @escaping FlutterResult) -> Void

class WindowEventsChannel: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        fatalError()
    }

    public static func register(returns registrar: FlutterPluginRegistrar)
        -> WindowEventsChannel
    {
        let channel = FlutterMethodChannel(
            name: "mixin.one/flutter_multi_window_events_channel",
            binaryMessenger: registrar.messenger)
        let instance = WindowEventsChannel(methodChannel: channel)

        registrar.addMethodCallDelegate(instance, channel: channel)
        return instance
    }

    var methodHandler: WindowMethodHandler?

    let methodChannel: FlutterMethodChannel

    init(methodChannel: FlutterMethodChannel) {
        self.methodChannel = methodChannel
        super.init()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as! [String: Any?]
        if let handler = methodHandler {
            handler(call.method, args, result)
        } else {
            debugPrint("method handler not set.")
        }
    }
}
