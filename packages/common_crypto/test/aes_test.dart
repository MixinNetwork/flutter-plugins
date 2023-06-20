import 'dart:convert';
import 'dart:math';

import 'package:common_crypto/common_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final Random _random = Random.secure();

Uint8List _generateRandomKey([int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => _random.nextInt(256)));

void main() {
  test('aseTest', () {
    final source = Uint8List.fromList(utf8.encode('mixin'));
    final key = _generateRandomKey(16);
    final iv = _generateRandomKey(16);
    final encrypted = aesEncrypt(
      key: key,
      data: source,
      iv: iv,
    );
    final decrypted = aesDecrypt(
      key: key,
      data: encrypted,
      iv: iv,
    );
    assert(listEquals(source, decrypted));
  });

  test('benchmark', () {
    final source = _generateRandomKey(1024 * 10); // 10kb data
    var totalTime = Duration.zero;
    for (var i = 0; i < 10000; i++) {
      final key = _generateRandomKey(16);
      final iv = _generateRandomKey(16);
      final stopwatch = Stopwatch()..start();
      final encrypted = aesEncrypt(
        key: key,
        data: source,
        iv: iv,
      );
      final decrypted = aesDecrypt(
        key: key,
        data: encrypted,
        iv: iv,
      );
      totalTime += stopwatch.elapsed;
      if (i % 1000 == 0) {
        debugPrint('benchmark aesEncrypt/aesDecrypt: $i times');
      }
      assert(listEquals(source, decrypted));
    }
    debugPrint('benchmark aesEncrypt/aesDecrypt: $totalTime');
  });
}
