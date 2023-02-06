import 'package:cross_file/cross_file.dart';
import 'package:flutter/painting.dart';
import 'dart:typed_data';
import 'package:meta/meta.dart';

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
  final List<XFile> files;
  final List<Uint8List?>? extraMacosBookmark; //macos : Uint8List//

  DropDoneEvent({
    required Offset location,
    required this.files,
    this.extraMacosBookmark,
  }) : super(location);

  @override
  String toString() {
    return '$runtimeType($location, $files)';
  }
}
