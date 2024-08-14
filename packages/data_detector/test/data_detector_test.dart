import 'dart:ui';

import 'package:data_detector/data_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("description", () {
    final detector = DataDetector(NSTextCheckingType.NSTextCheckingTypeLink);
    const str = "text: https://mixin.one";
    final results = detector.matchesInString(str);
    for (final result in results) {
      print('result: ${result.range.textInside(str)}');
    }
  });
}
