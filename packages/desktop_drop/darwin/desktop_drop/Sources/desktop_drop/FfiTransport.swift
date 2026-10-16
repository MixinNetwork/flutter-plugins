import Foundation
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
#if SWIFT_PACKAGE
import desktop_drop_ffi
#endif

final class FfiTransport {
  private final class Reply {
    let callback: FlutterResult
    init(_ callback: @escaping FlutterResult) { self.callback = callback }
  }
  private(set) var context: Int64 = 0
  var handler: ((FlutterMethodCall, @escaping FlutterResult) -> Void)?
  private let codec = FlutterStandardMethodCodec.sharedInstance()

  private let matches: ((Int64) -> Bool)?

  init(engine: Int64, matches: ((Int64) -> Bool)? = nil) {
    self.matches = matches
    context = dd_rpc_create(engine, { user, context, epoch, request, bytes, length in
      guard let user = user, let bytes = bytes else { return }
      let transport = Unmanaged<FfiTransport>.fromOpaque(user).takeUnretainedValue()
      let data = Data(bytes: bytes, count: Int(length))
      DispatchQueue.main.async { [weak transport] in
        guard let transport = transport else { return }
        let call = transport.codec.decodeMethodCall(data)
        let result: FlutterResult = { value in
          let data: Data
          if let error = value as? FlutterError {
            data = transport.codec.encodeErrorEnvelope(error)
          } else if (value as AnyObject?) === (FlutterMethodNotImplemented as AnyObject) {
            data = Data()
          } else {
            data = transport.codec.encodeSuccessEnvelope(value)
          }
          data.withUnsafeBytes {
            dd_rpc_reply(context, epoch, request, $0.bindMemory(to: UInt8.self).baseAddress, Int32(data.count))
          }
        }
        if let handler = transport.handler { handler(call, result) }
        else { result(FlutterMethodNotImplemented) }
      }
    }, Unmanaged.passUnretained(self).toOpaque(), { user, engine in
      guard let user = user else { return 0 }
      let transport = Unmanaged<FfiTransport>.fromOpaque(user).takeUnretainedValue()
      return transport.matches?(engine) == true ? 1 : 0
    })
  }
  deinit { dd_rpc_destroy(context) }

  func invoke(_ method: String, arguments: Any?, result: FlutterResult? = nil) {
    let data = codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))
    let user = result.map { Unmanaged.passRetained(Reply($0)).toOpaque() }
    _ = data.withUnsafeBytes { buffer in
      dd_rpc_send(context, buffer.bindMemory(to: UInt8.self).baseAddress, Int32(data.count),
        result == nil ? nil : { user, bytes, length in
          guard let user = user else { return }
          let reply = Unmanaged<Reply>.fromOpaque(user).takeRetainedValue()
          let data = bytes.map { Data(bytes: $0, count: Int(length)) } ?? Data()
          DispatchQueue.main.async {
            reply.callback(data.isEmpty ? FlutterMethodNotImplemented : FlutterStandardMethodCodec.sharedInstance().decodeEnvelope(data))
          }
        }, user)
    }
  }
}
