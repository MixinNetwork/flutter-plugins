import 'dart:js_interop';

import 'package:web/web.dart';
import 'package:flutter/foundation.dart';

import 'pasteboard_platform.dart';

Future<String?> _readBlobAsText(Blob blob) async {
  final FileReader reader = FileReader();
  final future =
      reader.onLoadEnd.first.then((ProgressEvent event) => reader.result);

  reader.readAsText(blob);

  final res = await future;
  return res.toString();
}

Clipboard get _clipboard => window.navigator.clipboard;

extension on Blob {
  Future<Uint8List?> _readAsUint8List() async {
    final buffer = await arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }
}

const PasteboardPlatform pasteboard = PasteboardPlatformWeb();

class PasteboardPlatformWeb implements PasteboardPlatform {
  const PasteboardPlatformWeb();

  @override
  Future<List<String>> files() async => const [];

  @override
  Future<String?> get html async {
    try {
      final clipboardItems = await _clipboard.read().toDart;
      for (var clipboardItem in clipboardItems.toDart) {
        if (clipboardItem.types.toDart.contains('text/html'.toJS)) {
          final blob = await clipboardItem.getType('text/html').toDart;
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
      final clipboardItems = await _clipboard.read().toDart;
      for (var item in clipboardItems.toDart) {
        for (var type in item.types.toDart) {
          if (type.toDart.startsWith('image/')) {
            final blob = await item.getType(type.toDart).toDart;
            return blob._readAsUint8List();
          }
        }
      }
    } catch (error, stacktrace) {
      debugPrint('get image failed: $error $stacktrace');
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
      final blob = Blob([image.toJS].toJS, BlobPropertyBag(type: 'image/png'));
      window.navigator.clipboard.write([
        ClipboardItem({'image/png': blob}.jsify()! as JSObject)
      ].toJS);
    } catch (e) {
      debugPrint('Error writing image to clipboard: $e');
      return;
    }
  }

  @override
  Future<String?> get text async {
    final data = await _clipboard.readText().toDart;
    return data.toDart;
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

void _select(HTMLTextAreaElement element) {
  final isReadOnly = element.hasAttribute('readonly');

  if (!isReadOnly) {
    element.setAttribute('readonly', '');
  }

  element
    ..select()
    ..setSelectionRange(0, element.value.length);

  if (!isReadOnly) {
    element.removeAttribute('readonly');
  }
}

/// https://github.com/zenorocha/clipboard.js/blob/master/src/common/create-fake-element.js
HTMLTextAreaElement _createCopyFakeElement(String value) {
  final isRtl = document.documentElement?.getAttribute('dir') == 'rtl';
  final fakeElement = HTMLTextAreaElement()
    // Prevent zooming on iOS
    ..style.fontSize = '12pt'
    // Reset box model
    ..style.border = '0'
    ..style.padding = '0'
    // Move element out of screen horizontally
    ..style.position = 'absolute'
    ..style.setProperty(isRtl ? 'right' : 'left', '-9999px');

  // Move element to the same position vertically
  final yPosition = window.pageYOffset.toInt() |
      (document.documentElement?.scrollTop.toInt() ?? 0);
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
