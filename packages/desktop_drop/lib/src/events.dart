import 'package:cross_file/cross_file.dart';
import 'package:flutter/painting.dart';

abstract class DropEvent {
  Offset location;

  DropEvent({required this.location});

  @override
  String toString() => '$runtimeType($location)';
}

class DropEnterEvent extends DropEvent {
  DropEnterEvent({required super.location});
}

class DropExitEvent extends DropEvent {
  DropExitEvent({required super.location});
}

class DropUpdateEvent extends DropEvent {
  DropUpdateEvent({required super.location});
}

class DropDoneEvent extends DropEvent {
  final List<XFile> files;

  DropDoneEvent({
    required super.location,
    required this.files,
  });

  @override
  String toString() => '$runtimeType($location, $files)';
}
