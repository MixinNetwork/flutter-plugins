import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pasteboard_platform.dart';

const PasteboardPlatform pasteboard = PasteboardPlatformIO();

class PasteboardPlatformIO implements PasteboardPlatform {
  const PasteboardPlatformIO();

  static const MethodChannel _channel = MethodChannel('pasteboard');

  @override
  Future<List<String>> files() async {
    final files = await _channel.invokeMethod<List>('files');
    return files?.cast<String>() ?? const [];
  }

  @override
  Future<String?> get html async {
    if (Platform.isWindows) {
      return await _channel.invokeMethod<Object>('html') as String?;
    }
    return null;
  }

  @override
  Future<Uint8List?> get image async {
    final image = await _channel.invokeMethod<Object>('image');

    if (image == null) {
      return null;
    }
    if (Platform.isMacOS || Platform.isLinux || Platform.isIOS) {
      return image as Uint8List;
    } else if (Platform.isWindows) {
      final file = File(image as String);
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes;
    }
    return null;
  }

  @override
  Future<bool> writeFiles(List<String> files) async {
    try {
      await _channel.invokeMethod<Object>('writeFiles', files);
      return true;
    } catch (error, stacktrace) {
      debugPrint('$error\n$stacktrace');
      return false;
    }
  }

  @override
  Future<void> writeImage(Uint8List? image) async {
    if (image == null) {
      return;
    }
    if (Platform.isIOS) {
      await _channel.invokeMethod<void>('writeImage', image);
    }
  }

  @override
  Future<String?> get text async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  void writeText(String value) {
    Clipboard.setData(ClipboardData(text: value));
  }
}
