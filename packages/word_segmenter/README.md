# word_segmenter

[![Pub](https://img.shields.io/pub/v/word_segmenter.svg)](https://pub.dev/packages/word_segmenter)

Splits text at word boundaries with the platform's own text services.

Flutter's engine bundles ICU without the CJK dictionary, so
`TextPainter.getWordBoundary` treats every Chinese or Japanese character as a
word. This package asks the operating system instead, which segments
`我们今天讨论一下` as `我们 | 今天 | 讨论 | 一下`.

| Platform | Backend |
| --- | --- |
| macOS, iOS | `CFStringTokenizer` |
| Windows | system `icu.dll` (Windows 10 1903+) |
| Linux | system `libicuuc` |
| Android | system `libicu.so` (API 31+) |
| Web | `Intl.Segmenter` |

No native code or plugin registration is needed: native platforms call the
system libraries through `dart:ffi`.

## Usage

```dart
import 'package:word_segmenter/word_segmenter.dart';

const text = 'Hello, 世界和平';
final ranges = wordBoundaries(text);
// ['Hello', ',', ' ', '世界', '和平']
print(ranges?.map((range) => range.textInside(text)).toList());
```

Segments are contiguous UTF-16 ranges covering the whole text; whitespace and
punctuation form their own segments. `wordBoundaries` returns `null` when the
platform has no segmenter available (for example Android below API 31), so
callers can fall back to `TextPainter.getWordBoundary`.

Exact segments come from the platform dictionaries and may differ slightly
between platforms.
