import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mixin_logger/mixin_logger.dart';
import 'package:mixin_logger/src/format.dart';

void main() {
  test('format', () {
    final time = DateTime.now();
    expect(
      formatDateTime(time),
      equals(DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(time)),
    );
    expect(
      formatDateTime(DateTime(1, 1, 1, 0, 0)),
      equals('0001-01-01 00:00:00.000'),
    );
    expect(
      formatDateTime(DateTime(2021, 1, 1, 0, 0)),
      equals('2021-01-01 00:00:00.000'),
    );
  });

  test('benchmark format', () {
    final DateTime time = DateTime.now();
    final stopwatch = Stopwatch()..start();
    i('formatDateTime: start');
    for (var i = 0; i < 100000; i++) {
      formatDateTime(time);
    }
    i('formatDateTime: ${stopwatch.elapsedMilliseconds}ms');
  });

  test('benchmark format2', () {
    final DateTime time = DateTime.now();
    final stopwatch = Stopwatch()..start();
    i('formatDateTime2: start');
    for (var i = 0; i < 100000; i++) {
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(time);
    }
    i('formatDateTime2: ${stopwatch.elapsedMilliseconds}ms');
  });
}
