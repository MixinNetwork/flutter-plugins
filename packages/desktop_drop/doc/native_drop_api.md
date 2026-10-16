# Native drop API comparison

Research snapshot: 2026-10-16. This note compares system contracts with the
Dart interface before its simplification; it does not propose an implementation change.

## System contracts

| Platform | Acceptance and feedback | Delivery and reads |
|----------|-------------------------|--------------------|
| macOS / AppKit | `draggingEntered` and `draggingUpdated` synchronously return `NSDragOperation`; `.none` rejects. | `prepareForDragOperation` can reject again; `performDragOperation` returns success. Pasteboard formats/data can be inspected before drop. |
| iOS / UIKit | `canHandle` returns Bool; `sessionDidUpdate` returns `UIDropProposal`. | `performDrop` returns Void. Start item-provider requests inside it; results arrive asynchronously. |
| Windows / OLE | `DragEnter` and `DragOver` synchronously write the selected effect. `IDataObject` exposes formats and data. | `Drop` reports the final effect. Optional `IDataObjectAsyncCapability` supports negotiated asynchronous extraction. |
| Linux / GTK3 | `drag-motion` handles the location; `gdk_drag_status` reports the action, possibly after asynchronous data inspection. | `drag-drop` requests data; `drag-data-received` processes it; `gtk_drag_finish` reports success and whether source data should be deleted. |
| Web | `dragenter` / `dragover` inspect types and kinds. Cancel events and set `dropEffect` to accept. | Capture strings and file references during `drop`; file bytes can be read afterward. |
| Android Views | `OnDragListener` switches on event actions. Returning true from `ACTION_DRAG_STARTED` subscribes to the drag. | `ACTION_DROP` exposes `ClipData` and synchronously returns a handled result, available through `ACTION_DRAG_ENDED.getResult()`. |

Sources:

- [AppKit receiving drag operations](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Tasks/acceptingdrags.html)
- [UIKit drop delegate](https://developer.apple.com/documentation/uikit/uidropinteractiondelegate)
- [UIKit performDrop data-request scope](https://developer.apple.com/documentation/uikit/uidropinteractiondelegate/dropinteraction(_:performdrop:))
- [Windows DragEnter](https://learn.microsoft.com/en-us/windows/win32/api/oleidl/nf-oleidl-idroptarget-dragenter)
- [Windows Drop](https://learn.microsoft.com/en-us/windows/win32/api/oleidl/nf-oleidl-idroptarget-drop)
- [Windows optional asynchronous extraction](https://learn.microsoft.com/en-us/windows/win32/api/shldisp/nn-shldisp-idataobjectasynccapability)
- [GTK3 drag-motion](https://docs.gtk.org/gtk3/signal.Widget.drag-motion.html)
- [GTK3 drag-drop](https://docs.gtk.org/gtk3/signal.Widget.drag-drop.html)
- [GTK3 drag-data-received](https://docs.gtk.org/gtk3/signal.Widget.drag-data-received.html)
- [HTML drag-and-drop standard](https://html.spec.whatwg.org/dev/dnd.html)
- [Android drag-and-drop concepts](https://developer.android.com/develop/ui/views/touch-and-input/drag-drop/concepts)

## Important distinctions

- Web protects content during hover; formats and kinds remain enumerable. This
  restriction does not apply uniformly to macOS, Windows, or GTK3.
- UIKit supports move within the same app when `allowsMoveOperation` permits it.
  Cross-app drops use copy. The plugin's current copy-only behavior is an
  implementation choice. See [UIDropOperation.move](https://developer.apple.com/documentation/uikit/uidropoperation/move).
- A UIKit file-provider temporary URL expires after its completion handler.
  Retaining content requires copying it before returning. See
  [loadFileRepresentation](https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation(fortypeidentifier:completionhandler:)).
- Native acceptance, data loading, and application processing have distinct
  completion semantics. A Dart Future cannot universally delay the native result.

## Higher-level reference

[GTK4 DropTarget](https://docs.gtk.org/gtk4/class.DropTarget.html) lets callers
configure accepted types and actions and handle the drop signal. Additional
acceptance and motion signals provide control when needed. DropTargetAsync is
available for finer transfer control. The current plugin uses GTK3; GTK4 is an
interface-design reference, not its runtime dependency.

[Flutter DragTarget](https://api.flutter.dev/flutter/widgets/DragTarget-class.html)
uses boolean `onWillAcceptWithDetails`, `onAcceptWithDetails`, `onMove`, `onLeave`,
and a builder. Its data is supplied by an in-Flutter Draggable; it does not solve
external provider permissions or asynchronous transfer lifetimes.

## Dart interface observations before the API simplification

- `DropTarget.onDropDecision` is required and returns an operation, even for a
  simple file-import target. A default copy policy could reduce caller work;
  unsupported operations would still have to reject safely.
- `DropEventDetails` is shared by decision requests and hover notifications.
  Its `operation` is reject during a decision and the chosen result afterward.
- `DropEvent` inherits the preview offer and adds readable items. Both describe
  content, but with different availability and purposes.
- `DropOffer.isComplete` is aggregate metadata. It cannot identify which item's
  name, value, or path is missing.
- Awaiting reads inside `onDrop` is the plugin's automatic-cleanup contract.
  It unifies several native lifetimes; every platform does not impose that exact
  Dart callback lifetime.

These are interface-design observations, not confirmed runtime defects.
