//
//  MessageChannelPlugin.swift
//  desktop_webview_window
//
//  Created by Bin Yang on 2021/11/19.
//

import FlutterMacOS
import Foundation

public class ClientMessageChannelPlugin: NSObject, FlutterPlugin {
  public init(methodChannel: FlutterMethodChannel) {
    self.methodChannel = methodChannel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "webview_message/client_channel", binaryMessenger: registrar.messenger)
    let instance = ClientMessageChannelPlugin(methodChannel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    ServerMessageChannel.shared.addClient(client: instance)
  }

  private let methodChannel: FlutterMethodChannel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    ServerMessageChannel.shared.dispatchMethodCall(call: call, from: self)
    // this is a boardcast, so we complete this with sucess.
    result(nil)
  }

  fileprivate func invokeMethod(_ call: FlutterMethodCall) {
    methodChannel.invokeMethod(call.method, arguments: call.arguments)
  }
}

class ServerMessageChannel {
  static let shared: ServerMessageChannel = ServerMessageChannel()

  // Registrars retain the plugins for the lifetime of their engine. The relay
  // must not keep dead engines' clients alive after the owner has shut down.
  private let clients = NSHashTable<ClientMessageChannelPlugin>.weakObjects()

  func addClient(client: ClientMessageChannelPlugin) {
    clients.add(client)
  }

  func removeClient(client: ClientMessageChannelPlugin) {
    clients.remove(client)
  }

  func dispatchMethodCall(call: FlutterMethodCall, from clientFrom: ClientMessageChannelPlugin) {
    for client in clients.allObjects {
      if client != clientFrom {
        client.invokeMethod(call)
      }
    }
  }
}
