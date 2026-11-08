/// Word segmentation backed by the platform's own text services.
library;

import 'dart:ui' show TextRange;

import 'src/segmenter_unsupported.dart'
    if (dart.library.js_interop) 'src/segmenter_web.dart'
    if (dart.library.ffi) 'src/segmenter_native.dart';

/// Splits [text] at word boundaries.
///
/// The returned segments are contiguous UTF-16 ranges that cover the whole
/// [text]: words, whitespace and punctuation each form their own segment.
/// Languages written without spaces, such as Chinese and Japanese, are split
/// with the platform's dictionaries, which Flutter's bundled ICU data leaves
/// out.
///
/// | Platform | Backend |
/// | --- | --- |
/// | macOS, iOS | `CFStringTokenizer` |
/// | Windows | system `icu.dll` (Windows 10 1903+) |
/// | Linux | system `libicuuc` |
/// | Android | system `libicu.so` (API 31+) |
/// | Web | `Intl.Segmenter` |
///
/// Returns null when the platform has no word segmenter available.
List<TextRange>? wordBoundaries(String text) => platformWordBoundaries(text);
