import Foundation
import UniformTypeIdentifiers
#if os(iOS)
import Flutter
import MobileCoreServices
#else
import FlutterMacOS
import CoreServices
#endif

func dropMimeType(_ identifier: String) -> String? {
  if #available(iOS 14.0, macOS 11.0, *) {
    return UTType(identifier)?.preferredMIMEType
  } else {
    return UTTypeCopyPreferredTagWithClass(identifier as CFString, kUTTagClassMIMEType)?
      .takeRetainedValue() as String?
  }
}

func dropTypeConforms(_ identifier: String, to parent: String) -> Bool {
  if #available(iOS 14.0, macOS 11.0, *) {
    guard let type = UTType(identifier), let parent = UTType(parent) else { return false }
    return type.conforms(to: parent)
  } else {
    return UTTypeConformsTo(identifier as CFString, parent as CFString)
  }
}

func dropError(_ code: String = "source_expired", _ message: String = "Dropped source is no longer available") -> FlutterError {
  FlutterError(code: code, message: message, details: nil)
}

// Session state is confined to the platform thread. Provider callbacks retain
// the session until their writes finish, even if Dart has already returned.
class DropResources {
  private final class Reader {
    let data: Data
    var offset: Int
    init(data: Data, start: Int64) {
      self.data = data
      offset = Int(min(start, Int64(data.count)))
    }
    func read(_ count: Int) -> Data {
      let end = min(data.count, offset + count)
      let bytes = data.subdata(in: offset..<end)
      offset = end
      return bytes
    }
  }
  let generation: Int64
  var directory: URL?
  var pendingLoads = 0
  private(set) var released = false
  private var readers: [Int64: Reader] = [:]
  private var nextReader: Int64 = 0

  init(generation: Int64) { self.generation = generation }
  deinit {
    if let directory = directory { try? FileManager.default.removeItem(at: directory) }
  }
  func temporaryDirectory() throws -> URL {
    if let directory = directory { return directory }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("desktop-drop-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    return directory
  }
  func cleanup() {
    if released && pendingLoads == 0, let directory = directory {
      try? FileManager.default.removeItem(at: directory)
      self.directory = nil
    }
  }
  func release() {
    guard !released else { return }
    released = true
    readers.removeAll()
    cleanup()
  }
  func read(_ args: [String: Any], result: FlutterResult) -> Bool {
    let operation = args["op"] as? String ?? ""
    let stream = (args["stream"] as? NSNumber)?.int64Value ?? -1
    if operation == "close" { readers.removeValue(forKey: stream); result(nil); return true }
    guard operation == "read" else { return false }
    let count = (args["count"] as? NSNumber)?.intValue ?? 65536
    guard !released, let reader = readers[stream], count > 0, count <= 65536 else {
      result(dropError()); return true
    }
    result(FlutterStandardTypedData(bytes: reader.read(count)))
    return true
  }
  func open(_ data: Data, args: [String: Any], result: FlutterResult) {
    let start = (args["start"] as? NSNumber)?.int64Value ?? 0
    guard !released else { result(dropError()); return }
    guard start >= 0 else { result(dropError("invalid_range", "Invalid read offset")); return }
    nextReader += 1
    readers[nextReader] = Reader(data: data, start: start)
    result(nextReader)
  }
}
