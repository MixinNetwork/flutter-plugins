//
//  WindowChannel.swift
//  desktop_multi_window
//
//  Created by Bin Yang on 2022/1/28.
//

import FlutterMacOS
import Foundation

typealias ChannelId = String

/// Channel communication mode
enum ChannelMode: String {
  /// Unidirectional mode: All engines can invoke this channel
  case unidirectional = "unidirectional"
  /// Bidirectional mode: Only paired engines can invoke each other
  case bidirectional = "bidirectional"
}

private class ChannelRegistry {
  static let shared = ChannelRegistry()

  private let lock = NSLock()
  
  // Unidirectional channels: channel -> single window
  private var unidirectionalChannels = [String: WeakBox<WindowChannel>]()
  
  // Bidirectional channels: channel -> pair of windows
  private var bidirectionalChannels = [String: NSHashTable<AnyObject>]()

  enum RegistrationOutcome {
    case added
    case alreadyRegistered
    case limitReached
    case modeConflict
  }

  private init() {}
  
  // Helper class to wrap weak reference
  private class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
      self.value = value
    }
  }

  @discardableResult
  func register(_ channel: String, window: WindowChannel, mode: ChannelMode) -> RegistrationOutcome {
    lock.lock(); defer { lock.unlock() }
    
    switch mode {
    case .unidirectional:
      return registerUnidirectional(channel, window: window)
    case .bidirectional:
      return registerBidirectional(channel, window: window)
    }
  }
  
  private func registerUnidirectional(_ channel: String, window: WindowChannel) -> RegistrationOutcome {
    // Check if channel is already used in bidirectional mode
    if bidirectionalChannels[channel] != nil {
      return .modeConflict
    }
    
    if let existing = unidirectionalChannels[channel]?.value {
      if existing === window {
        return .alreadyRegistered
      }
      // Already registered by another window
      return .limitReached
    }
    
    unidirectionalChannels[channel] = WeakBox(window)
    return .added
  }
  
  private func registerBidirectional(_ channel: String, window: WindowChannel) -> RegistrationOutcome {
    // Check if channel is already used in unidirectional mode
    if unidirectionalChannels[channel] != nil {
      return .modeConflict
    }
    
    let table: NSHashTable<AnyObject>
    if let existing = bidirectionalChannels[channel] {
      table = existing
    } else {
      table = NSHashTable<AnyObject>.weakObjects()
      bidirectionalChannels[channel] = table
    }

    let activeWindows = table.allObjects.compactMap { $0 as? WindowChannel }

    if activeWindows.contains(where: { $0 === window }) {
      return .alreadyRegistered
    }

    if activeWindows.count >= 2 {
      return .limitReached
    }

    table.add(window)
    return .added
  }

  func unregister(_ channel: String, window: WindowChannel) {
    lock.lock(); defer { lock.unlock() }
    
    // Try unidirectional
    if let existing = unidirectionalChannels[channel]?.value, existing === window {
      unidirectionalChannels.removeValue(forKey: channel)
      return
    }
    
    // Try bidirectional
    if let table = bidirectionalChannels[channel] {
      table.remove(window)
      if table.allObjects.isEmpty {
        bidirectionalChannels.removeValue(forKey: channel)
      }
    }
  }

  func getTarget(for channel: String, from window: WindowChannel) -> WindowChannel? {
    lock.lock(); defer { lock.unlock() }
    
    // Check unidirectional
    if let target = unidirectionalChannels[channel]?.value {
      // Anyone can call unidirectional channel
      return target
    }
    
    // Check bidirectional - only peer can call
    if let table = bidirectionalChannels[channel] {
      let candidates = table.allObjects.compactMap { $0 as? WindowChannel }
      if candidates.isEmpty {
        bidirectionalChannels.removeValue(forKey: channel)
        return nil
      }
      
      // Check if caller is in the pair
      guard candidates.contains(where: { $0 === window }) else {
        return nil
      }
      
      // Return the peer
      return candidates.first { $0 !== window }
    }
    
    return nil
  }
  
  func hasRegistrations(for channel: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    
    if let box = unidirectionalChannels[channel], box.value != nil {
      return true
    }
    
    if let table = bidirectionalChannels[channel] {
      let hasActive = !table.allObjects.isEmpty
      if !hasActive {
        bidirectionalChannels.removeValue(forKey: channel)
      }
      return hasActive
    }
    
    return false
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
      let modeString = arguments["mode"] as? String ?? "bidirectional"
      
      guard let mode = ChannelMode(rawValue: modeString) else {
        result(
          FlutterError(
            code: "INVALID_MODE",
            message: "invalid mode: \(modeString), must be 'unidirectional' or 'bidirectional'",
            details: nil))
        return
      }

      let outcome = ChannelRegistry.shared.register(channel, window: self, mode: mode)
      switch outcome {
      case .added:
        methodChannels.append(channel)
        result(nil)
      case .alreadyRegistered:
        result(nil)
      case .limitReached:
        let message = mode == .unidirectional 
          ? "channel \(channel) already registered in unidirectional mode"
          : "channel \(channel) already has the maximum number of registrations (2)"
        result(
          FlutterError(
            code: "CHANNEL_LIMIT_REACHED",
            message: message,
            details: nil))
      case .modeConflict:
        result(
          FlutterError(
            code: "CHANNEL_MODE_CONFLICT",
            message: "channel \(channel) is already registered in a different mode",
            details: nil))
      }
    case "unregisterMethodHandler":
      let arguments = call.arguments as! [String: Any?]
      let channel = arguments["channel"] as! String

      ChannelRegistry.shared.unregister(channel, window: self)

      if let index = methodChannels.firstIndex(of: channel) {
        methodChannels.remove(at: index)
      }

      result(nil)
    case "invokeMethod":
      let arguments = call.arguments as! [String: Any?]
      let channel = arguments["channel"] as! String

      if let targetChannel = ChannelRegistry.shared.getTarget(for: channel, from: self) {
        targetChannel.invokeMethod(channel: channel, arguments: call.arguments, result: result)
      } else {
        let message: String
        if ChannelRegistry.shared.hasRegistrations(for: channel) {
          message = "channel \(channel) not accessible from this engine (may be bidirectional pair or not registered)"
        } else {
          message = "unknown registered channel \(channel)"
        }
        result(
          FlutterError(
            code: "CHANNEL_UNREGISTERED", message: message,
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
    for channel in methodChannels {
      ChannelRegistry.shared.unregister(channel, window: self)
    }
  }
}
