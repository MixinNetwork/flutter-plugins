import Flutter
import UIKit
import UniformTypeIdentifiers
import MobileCoreServices



public class DesktopDropPlugin: NSObject, FlutterPlugin, UIDropInteractionDelegate {
  static var sharedInstance: DesktopDropPlugin?

  private var channel: FlutterMethodChannel?
  private var dropView: UIView?
    private let supportedTypes = [
           "public.file-url",   // Files from Files app or Finder
           "public.url",        // URLs, including local and remote
           "public.image",      // Images (PNG, JPEG, etc.)
           "public.movie",      // Video files (MP4, MOV)
           "public.audio",      // Audio files (MP3, WAV)
           "public.text",       // Plain text
           "public.data",       // Arbitrary binary data
           "public.content",    // Abstract type for all user data
           "public.item",       // Abstract type for any drag item
           "com.adobe.pdf"      // PDF documents
       ]

  // MARK: - Plugin Registration

  public static func register(with registrar: FlutterPluginRegistrar) {

    let instance = DesktopDropPlugin()
    sharedInstance = instance

    let channel = FlutterMethodChannel(name: "desktop_drop", binaryMessenger: registrar.messenger())
      
    instance.channel = channel

 channel.setMethodCallHandler { call, result in
        instance.handle(call, result: result)
    }
    // Attach drop view after app is active
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      instance.attachDropView()
    }
  }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

        if call.method == "startAccessingSecurityScopedResource" {

            guard let map = call.arguments as? [String: Any],
                  let bookmarkByte = map["apple-bookmark"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid bookmark", details: nil))
                return
            }

            var isStale = false
            let bookmark = bookmarkByte.data

            do {
                let url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
                let success = url.startAccessingSecurityScopedResource()
                result(success)
            } catch {
                result(FlutterError(code: "BOOKMARK_ERROR", message: "Failed to resolve bookmark", details: error.localizedDescription))
            }
            return
        }

        if call.method == "stopAccessingSecurityScopedResource" {

            guard let map = call.arguments as? [String: Any],
                  let bookmarkByte = map["apple-bookmark"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid bookmark", details: nil))
                return
            }

            var isStale = false
            let bookmark = bookmarkByte.data

            do {
                let url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
                url.stopAccessingSecurityScopedResource()
                result(true)
            } catch {
                result(FlutterError(code: "BOOKMARK_ERROR", message: "Failed to resolve bookmark", details: error.localizedDescription))
            }
            return
        }

        result(FlutterMethodNotImplemented)
    }



  // MARK: - Attach Drop View

  private func attachDropView() {
    guard let rootVC = UIApplication.shared.delegate?.window??.rootViewController else {
      return
    }

    guard self.dropView == nil else {
      return
    }

    let dropView = UIView(frame: rootVC.view.bounds)
    dropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    dropView.isUserInteractionEnabled = true
    dropView.backgroundColor = UIColor.clear

    let interaction = UIDropInteraction(delegate: self)
    dropView.addInteraction(interaction)

    rootVC.view.addSubview(dropView)
    self.dropView = dropView

  }


  // MARK: - UIDropInteractionDelegate

    public func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
      
        let canHandle = session.hasItemsConforming(toTypeIdentifiers: self.supportedTypes)
        return canHandle
    }


    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
        if let view = self.dropView {
            let location = session.location(in: view)
            channel?.invokeMethod("entered", arguments: [Double(location.x), Double(location.y)])
        } else {
            channel?.invokeMethod("entered", arguments: [0.0, 0.0])
        }
    }

    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        if let view = self.dropView {
            let location = session.location(in: view)
            channel?.invokeMethod("updated", arguments: [Double(location.x), Double(location.y)])
        }
        return UIDropProposal(operation: .copy)
    }

  public func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
    channel?.invokeMethod("exited", arguments: nil)
  }

    public func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let resultItems = NSMutableArray()
        let dispatchGroup = DispatchGroup()

        for item in session.items {
            let provider = item.itemProvider
            dispatchGroup.enter()

            guard let typeToLoad = self.supportedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
                dispatchGroup.leave()
                continue
            }

            provider.loadFileRepresentation(forTypeIdentifier: typeToLoad) { url, error in
                if let url = url {
                    let fileName = url.lastPathComponent
                    let mime = self.mimeType(for: url)
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + fileName)

                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        let bookmark = try? tempURL.bookmarkData()

                        resultItems.add([
                            "path": tempURL.path,
                            "name": fileName,
                            "mime": mime,
                            "apple-bookmark": bookmark as Any,
                        ])
                        dispatchGroup.leave()
                    } catch {
                        self.handleFallback(
                            provider: provider,
                            typeIdentifier: typeToLoad,
                            resultItems: resultItems,
                            dispatchGroup: dispatchGroup,
                            fallbackURL: url
                        )
                    }
                } else {
                    self.handleFallback(
                        provider: provider,
                        typeIdentifier: typeToLoad,
                        resultItems: resultItems,
                        dispatchGroup: dispatchGroup
                    )
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            self.channel?.invokeMethod("performOperation_ios", arguments: resultItems)
        }
    }
    private func handleFallback(
        provider: NSItemProvider,
        typeIdentifier: String,
        resultItems: NSMutableArray,
        dispatchGroup: DispatchGroup,
        fallbackURL: URL? = nil
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            defer { dispatchGroup.leave() }

            guard let data = data else {
                return
            }

            let ext = (fallbackURL?.pathExtension.isEmpty == false ? fallbackURL!.pathExtension : self.extensionFromUTI(typeIdentifier))

            let baseName = fallbackURL?.deletingPathExtension().lastPathComponent ?? "Dropped_\(UUID().uuidString)"
            let fileName = typeIdentifier == "public.image" ? baseName + ".png" : "\(baseName).\(ext)"
            let mime = self.mimeTypeFromData(data, fallbackExt: ext)

            self.addResultItem(
                data: data,
                name: fileName,
                mime: mime,
                typeIdentifier: typeIdentifier,
                resultItems: resultItems
            )
        }
    }

    private func addResultItem(
        data: Data,
        name: String,
        mime: String,
        typeIdentifier: String,
        resultItems: NSMutableArray
    ) {
        if typeIdentifier == "public.image", let image = UIImage(data: data), let pngData = image.pngData() {
            resultItems.add([
                "path": nil,
                "name": name,
                "mime": "image/png",
                "length": pngData.count,
                "bytes": FlutterStandardTypedData(bytes: pngData)
            ])
        } else {
            resultItems.add([
                "path": nil,
                "name": name,
                "mime": mime,
                "length": data.count,
                "bytes": FlutterStandardTypedData(bytes: data)
            ])
        }
    }





    func mimeType(for url: URL) -> String {
           let ext = url.pathExtension
           if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue(),
              let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
               return mime as String
           }
           return "application/octet-stream"
       }

       func extensionFromUTI(_ uti: String) -> String {
           if let ext = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassFilenameExtension)?.takeRetainedValue() {
               return ext as String
           }
           return "bin"
       }

       func mimeTypeFromData(_ data: Data, fallbackExt: String) -> String {
           // Basic detection or just fallback
           switch fallbackExt.lowercased() {
           case "png": return "image/png"
           case "jpg", "jpeg": return "image/jpeg"
           case "pdf": return "application/pdf"
           case "mp3": return "audio/mpeg"
           case "mp4": return "video/mp4"
           default: return "application/octet-stream"
           }
       }



}
