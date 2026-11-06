import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui';

import 'package:objective_c/objective_c.dart' as objc;

import 'src/data_detector_bindings_generated.dart' as binding;

export 'src/data_detector_bindings_generated.dart'
    show NSTextCheckingType, NSMatchingOptions;

extension on TextRange {
  objc.NSRange toNSRange() {
    final range = Struct.create<objc.NSRange>(
      Uint8List(sizeOf<objc.NSRange>()),
    );
    range.location = start;
    range.length = end - start;
    return range;
  }
}

class TextCheckingResult {
  TextCheckingResult._(this._inner);

  final binding.NSTextCheckingResult _inner;

  int get type => _inner.resultType;

  TextRange get range {
    final range = _inner.range;
    final textRange =
        TextRange(start: range.location, end: range.location + range.length);
    return textRange;
  }

  DateTime? get date {
    final timestamp = _inner.date?.timeIntervalSince1970;
    if (timestamp == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch((timestamp * 1e6).round());
  }

  Duration get duration =>
      Duration(microseconds: (_inner.duration * 1e6).round());

  Uri? get url {
    final url = _inner.URL?.absoluteString;
    if (url == null) {
      return null;
    }
    return Uri.parse(url.toString());
  }
}

class DataDetector {
  factory DataDetector(int type) {
    final detector = binding.NSDataDetector.alloc().initWithTypes(type);
    return DataDetector._(detector!);
  }

  DataDetector._(this._detector);

  final binding.NSDataDetector _detector;

  List<TextCheckingResult> matchesInString(
    String str, {
    int? options,
    TextRange? range,
  }) {
    final nsRange = (range ?? TextRange(start: 0, end: str.length)).toNSRange();
    final array = _detector.matchesInString(str.toNSString(),
        options:
            options ?? binding.NSMatchingOptions.NSMatchingReportCompletion,
        range: nsRange);

    final results = <TextCheckingResult>[];
    for (var i = 0; i < array.count; i++) {
      final result = binding.NSTextCheckingResult.as(array.objectAtIndex(i));
      results.add(TextCheckingResult._(result));
    }
    return results;
  }
}
