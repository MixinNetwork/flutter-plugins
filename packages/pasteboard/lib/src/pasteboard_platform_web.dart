// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html';
import 'dart:js_util';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:js/js.dart';

import 'pasteboard_platform.dart';

@JS('navigator.clipboard.read')
external List<ClipboardItem> _readClipboard();

@JS('navigator.clipboard.write')
external void _writeClipboard(List<ClipboardItem> data);

@JS('ClipboardItem')
class ClipboardItem {
  external ClipboardItem(dynamic data);

  external List<String> get types;

  external Blob getType(String type);
}

Future<String?> _readBlobAsText(Blob blob) async {
  final FileReader reader = FileReader();
  final future =
      reader.onLoad.first.then((ProgressEvent event) => reader.result);

  reader.readAsText(blob);

  final res = await future;
  return res.toString();
}

Future<Uint8List?> _readBlobAsArrayBuffer(Blob blob) async {
  final FileReader reader = FileReader();
  final future =
      reader.onLoad.first.then((ProgressEvent event) => reader.result);

  reader.readAsArrayBuffer(blob);

  final res = await future;
  return res as Uint8List?;
}

const PasteboardPlatform pasteboard = PasteboardPlatformWeb();

class PasteboardPlatformWeb implements PasteboardPlatform {
  const PasteboardPlatformWeb();

  @override
  Future<List<String>> files() async => const [];

  @override
  Future<String?> get html async {
    try {
      final clipboardItems =
          await promiseToFuture(_readClipboard()) as List<dynamic>;
      for (var clipboardItem in clipboardItems.cast<ClipboardItem>()) {
        if (clipboardItem.types.contains('text/html')) {
          final Blob blob =
              await promiseToFuture(clipboardItem.getType('text/html'));
          return _readBlobAsText(blob);
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Future<Uint8List?> get image async {
    try {
      final clipboardItems =
          await promiseToFuture(_readClipboard()) as List<dynamic>;
      for (var clipboardItem in clipboardItems.cast<ClipboardItem>()) {
        if (clipboardItem.types.contains('image/png')) {
          final Blob blob =
              await promiseToFuture(clipboardItem.getType('image/png'));
          return _readBlobAsArrayBuffer(blob);
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Future<bool> writeFiles(List<String> files) async => false;

  @override
  Future<void> writeImage(Uint8List? image) async {
    if (image == null) {
      return;
    }
    try {
      final blob = Blob([image], 'image/png');
      _writeClipboard([
        ClipboardItem(jsify({'image/png': blob}))
      ]);
    } catch (e) {
      debugPrint('Error writing image to clipboard: $e');
      return;
    }
  }

  @override
  Future<String?> get text async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  void writeText(String value) {
    final fakeElement = _createCopyFakeElement(value)..select();
    document.body?.append(fakeElement);
    _select(fakeElement);
    _copyCommand();
    fakeElement.remove();
  }
}

void _select(TextAreaElement element) {
  final isReadOnly = element.hasAttribute('readonly');

  if (!isReadOnly) {
    element.setAttribute('readonly', '');
  }

  element
    ..select()
    ..setSelectionRange(0, element.value?.length ?? 0);

  if (!isReadOnly) {
    element.removeAttribute('readonly');
  }
}

/// https://github.com/zenorocha/clipboard.js/blob/master/src/common/create-fake-element.js
TextAreaElement _createCopyFakeElement(String value) {
  final isRtl = document.documentElement?.getAttribute('dir') == 'rtl';
  final fakeElement = TextAreaElement()
    // Prevent zooming on iOS
    ..style.fontSize = '12pt'
    // Reset box model
    ..style.border = '0'
    ..style.padding = '0'
    // Move element out of screen horizontally
    ..style.position = 'absolute'
    ..style.setProperty(isRtl ? 'right' : 'left', '-9999px');

  // Move element to the same position vertically
  final yPosition =
      window.pageYOffset | (document.documentElement?.scrollTop ?? 0);
  fakeElement
    ..style.top = '${yPosition}px'
    ..setAttribute('readonly', '')
    ..value = value;
  return fakeElement;
}

bool _copyCommand() {
  try {
    return document.execCommand('copy');
  } catch (error, stack) {
    window.alert('$error, $stack');
    // ignore
    return false;
  }
}
