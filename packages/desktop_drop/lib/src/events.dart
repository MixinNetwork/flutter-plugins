import 'package:desktop_drop/src/drop_item.dart';
import 'package:flutter/painting.dart';

abstract class DropEvent {
  Offset location;

  DropEvent(this.location);

  @override
  String toString() {
    return '$runtimeType($location)';
  }
}

class DropEnterEvent extends DropEvent {
  DropEnterEvent({required Offset location}) : super(location);
}

class DropExitEvent extends DropEvent {
  DropExitEvent({required Offset location}) : super(location);
}

class DropUpdateEvent extends DropEvent {
  DropUpdateEvent({required Offset location}) : super(location);
}

class DropDoneEvent extends DropEvent {
  final List<DropItem> files;

  /// The raw text payload from the drag operation.
  ///
  /// Format: one URI or token per line (as delivered by GTK).
  ///
  /// On Linux/Wayland with Flatpak, this contains the portal key(s)
  /// from the `application/vnd.portal.filetransfer` mimetype — a
  /// random string token that can be passed to
  /// `org.freedesktop.portal.FileTransfer.RetrieveFiles` to get
  /// sandbox-accessible file paths.
  ///
  /// Example content:
  /// ```
  /// file:///home/user/Downloads/normal.txt
  /// file:///home/user/Documents/portal.txt
  /// abc123portalkey456
  /// ```
  ///
  /// The portal key line is NOT a file URI and can be distinguished
  /// by not starting with `file://`. It is only present when the
  /// drag source used the XDG Desktop Portal (typical for sandboxed
  /// apps on Wayland).
  ///
  /// Is `null` on platforms where raw text isn't exposed (Windows,
  /// macOS, or when the platform channel doesn't provide it).
  final String? rawText;

  DropDoneEvent({
    required Offset location,
    required this.files,
    this.rawText,
  }) : super(location);

  @override
  String toString() {
    return '$runtimeType($location, $files, rawText: $rawText)';
  }
}
