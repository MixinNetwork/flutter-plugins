import Foundation
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
#if SWIFT_PACKAGE
import desktop_drop_ffi
#endif

func decideDrop(context: Int64, session: Int64, phase: Int32, point: CGPoint,
                mask: Int, offer: [String: Any], full: Bool) -> DDDecision {
  func request(full: Bool) -> DDDecision {
    var args: [String: Any] = ["operationMask": mask]
    if full { args["offer"] = offer }
    let payload = FlutterStandardMessageCodec.sharedInstance().encode(args)!
    return payload.withUnsafeBytes {
      dd_bridge_decide(context, session, phase, point.x, point.y,
                       $0.bindMemory(to: UInt8.self).baseAddress, Int32(payload.count))
    }
  }
  let decision = request(full: full)
  return decision.target == -1 ? request(full: true) : decision
}

func dropEvent(view: Int64, session: Int64, phase: Int32, point: CGPoint,
               mask: Int, decision: DDDecision) -> [String: Any] {
  ["view": view, "session": session, "generation": decision.generation,
   "request": decision.request, "target": decision.target, "phase": phase,
   "operation": decision.operation, "x": point.x, "y": point.y, "operationMask": mask]
}
