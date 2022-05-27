// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'pasteboard_platform.dart';

const PasteboardPlatform pasteboard = PasteboardPlatformWeb();

class PasteboardPlatformWeb implements PasteboardPlatform {
  const PasteboardPlatformWeb();

  @override
  Future<List<String>> files() async => const [];

  @override
  Future<String?> get html async => null;

  @override
  Future<Uint8List?> get image async => null;

  @override
  Future<bool> writeFiles(List<String> files) async => false;

  @override
  Future<void> writeImage(Uint8List? image) async {}

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
