//
//  WindowChannel.swift
//  desktop_multi_window
//
//  Created by Bin Yang on 2022/1/28.
//

import FlutterMacOS
import Foundation

typealias InterWindowMethodHandler = (Int64, Int64, String, Any?, @escaping FlutterResult) -> Void

class InterWindowEventChannel: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    fatalError()
  }

  public static func register(with registrar: FlutterPluginRegistrar, windowId: Int64)
    -> InterWindowEventChannel
  {
    let channel = FlutterMethodChannel(
      name: "mixin.one/flutter_multi_window_inter_window_event_channel",
      binaryMessenger: registrar.messenger)
    let instance = InterWindowEventChannel(windowId: windowId, methodChannel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    return instance
  }

  var methodHandler: InterWindowMethodHandler?

  let methodChannel: FlutterMethodChannel

  private let windowId: Int64

  init(windowId: Int64, methodChannel: FlutterMethodChannel) {
    self.windowId = windowId
    self.methodChannel = methodChannel
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as! [String: Any?]
    let targetWindowId = args["targetWindowId"] as! Int64
    let arguments = args["arguments"] ?? nil
    if let handler = methodHandler {
      handler(windowId, targetWindowId, call.method, arguments, result)
    } else {
      debugPrint("method handler not set.")
    }
  }

  func invokeMethod(
    fromWindowId: Int64, method: String, arguments: Any?, result: @escaping FlutterResult
  ) {
    let args = [
      "fromWindowId": fromWindowId,
      "arguments": arguments,
    ]
    methodChannel.invokeMethod(method, arguments: args, result: result)
  }
}
