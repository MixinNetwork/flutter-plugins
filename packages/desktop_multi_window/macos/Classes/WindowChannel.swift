//
//  WindowChannel.swift
//  desktop_multi_window
//
//  Created by Bin Yang on 2022/1/28.
//

import FlutterMacOS
import Foundation

typealias ChannelId = String

private class ChannelRegistry {
  static let shared = ChannelRegistry()

  private let lock = NSLock()
  private let map = NSMapTable<NSString, AnyObject>.strongToWeakObjects()

  private init() {}

  func register(_ channel: String, window: WindowChannel) {
    lock.lock(); defer { lock.unlock() }
    map.setObject(window as AnyObject, forKey: channel as NSString)
  }

  func unregister(_ channel: String) {
    lock.lock(); defer { lock.unlock() }
    map.removeObject(forKey: channel as NSString)
  }

  func get(_ channel: String) -> WindowChannel? {
    lock.lock(); defer { lock.unlock() }
    return map.object(forKey: channel as NSString) as? WindowChannel
  }

  func contains(_ channel: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return map.object(forKey: channel as NSString) != nil
  }
}


class WindowChannel: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mixin.one/desktop_multi_window/channels", binaryMessenger: registrar.messenger)
    let instance = WindowChannel(methodChannel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  init(methodChannel: FlutterMethodChannel) {
    self.methodChannel = methodChannel
    super.init()
  }

  private let methodChannel: FlutterMethodChannel

  private var methodChannels: [String] = []

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "registerMethodHandler":
      let arguments = call.arguments as! [String: Any?]
      let channel = arguments["channel"] as! String

      // check if channel already registered
      if ChannelRegistry.shared.contains(channel) {
        result(
          FlutterError(
            code: "CHANNEL_ALREADY_REGISTERED", message: "channel \(channel) already registered",
            details: nil))
        return
      }
      ChannelRegistry.shared.register(channel, window: self)

      methodChannels.append(channel)

      result(nil)
    case "unregisterMethodHandler":
      let arguments = call.arguments as! [String: Any?]
      let channel = arguments["channel"] as! String

      ChannelRegistry.shared.unregister(channel)

      if let index = methodChannels.firstIndex(of: channel) {
        methodChannels.remove(at: index)
      }

      result(nil)
    case "invokeMethod":
      let arguments = call.arguments as! [String: Any?]
      let channel = arguments["channel"] as! String

      if let targetChannel = ChannelRegistry.shared.get(channel) {
        targetChannel.invokeMethod(channel: channel, arguments: call.arguments, result: result)
      } else {
        result(
          FlutterError(
            code: "CHANNEL_UNREGISTERED", message: "unknown registered channel \(channel)",
            details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func invokeMethod(channel: String, arguments: Any?, result: @escaping FlutterResult) {
    // check channelIds contains channel
    if !methodChannels.contains(channel) {
      result(
        FlutterError(
          code: "CHANNEL_NOT_FOUND", message: "channel \(channel) not found in this engine",
          details: nil))
      return
    }
    methodChannel.invokeMethod("methodCall", arguments: arguments, result: result)
  }

  deinit {
      debugPrint("WindowChannel deinit")
    for channel in methodChannels {
      ChannelRegistry.shared.unregister(channel)
    }
  }
}
