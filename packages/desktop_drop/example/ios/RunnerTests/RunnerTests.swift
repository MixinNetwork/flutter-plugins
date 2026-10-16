import Flutter
import UIKit
import XCTest

private final class ChangingDragItem: UIDragItem {
  var dropProvider: NSItemProvider?
  override var itemProvider: NSItemProvider {
    dropProvider ?? super.itemProvider
  }
}

private final class TestDropSession: NSObject, UIDropSession {
  let items: [UIDragItem]
  let allowsMoveOperation = false
  let isRestrictedToDraggingApplication = false
  let localDragSession: UIDragSession? = nil
  let progress = Progress(totalUnitCount: 1)
  var progressIndicatorStyle: UIDropSessionProgressIndicatorStyle = .none

  init(item: UIDragItem) { items = [item] }
  func location(in view: UIView) -> CGPoint { CGPoint(x: 60, y: 180) }
  func hasItemsConforming(toTypeIdentifiers identifiers: [String]) -> Bool {
    items.contains { item in
      identifiers.contains { item.itemProvider.hasItemConformingToTypeIdentifier($0) }
    }
  }
  func canLoadObjects(ofClass aClass: NSItemProviderReading.Type) -> Bool { false }
  func loadObjects(ofClass aClass: NSItemProviderReading.Type,
                   completion: @escaping ([NSItemProviderReading]) -> Void) -> Progress {
    completion([])
    return progress
  }
}

final class RunnerTests: XCTestCase {
  func testDropLoadsCurrentProviderAfterHover() throws {
    // Exercise the installed plugin through its actual UIKit delegate. The
    // drag item stays the same while UIKit replaces its provider at release.
    var destination: (UIView, UIDropInteraction)?
    func find(in view: UIView) -> (UIView, UIDropInteraction)? {
      if let interaction = view.interactions.compactMap({ $0 as? UIDropInteraction })
        .first(where: { interaction in
          guard let delegate = interaction.delegate else { return false }
          return String(describing: type(of: delegate)).contains("DesktopDropPlugin")
        }) {
        return (view, interaction)
      }
      return view.subviews.lazy.compactMap { find(in: $0) }.first
    }
    let deadline = Date().addingTimeInterval(10)
    while destination == nil && Date() < deadline {
      for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        destination = scene.windows.lazy.compactMap { find(in: $0) }.first
        if destination != nil { break }
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    let (_, interaction) = try XCTUnwrap(destination)
    let delegate = try XCTUnwrap(interaction.delegate)
    let loaded = expectation(description: "The provider supplied at release is loaded")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop-provider-test.jpg")
    try Data([0xff, 0xd8, 0xff, 0xd9]).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    let hoverProvider = NSItemProvider()
    hoverProvider.registerFileRepresentation(forTypeIdentifier: "public.jpeg", fileOptions: [], visibility: .all) { completion in
      XCTFail("The metadata-only hover provider must not be used for loading")
      completion(file, false, nil)
      return nil
    }
    let dropProvider = NSItemProvider()
    dropProvider.registerFileRepresentation(forTypeIdentifier: "public.jpeg", fileOptions: [], visibility: .all) { completion in
      loaded.fulfill()
      completion(file, false, nil)
      return nil
    }
    let item = ChangingDragItem(itemProvider: hoverProvider)
    let session = TestDropSession(item: item)
    delegate.dropInteraction?(interaction, sessionDidEnter: session)
    XCTAssertEqual(delegate.dropInteraction?(interaction, sessionDidUpdate: session).operation, .copy)
    item.dropProvider = dropProvider
    delegate.dropInteraction?(interaction, performDrop: session)
    wait(for: [loaded], timeout: 3)
    delegate.dropInteraction?(interaction, sessionDidEnd: session)
  }
}
