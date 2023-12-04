import 'dart:convert';
import 'dart:math';

import 'package:common_crypto/common_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final Random _random = Random.secure();

Uint8List generateRandomBytes([int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => _random.nextInt(256)));

void main() {
  test('aseTest', () {
    final source = Uint8List.fromList(utf8.encode('mixin'));
    final key = generateRandomBytes(16);
    final iv = generateRandomBytes(16);
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
    final source = generateRandomBytes(1024 * 10); // 10kb data
    var totalTime = Duration.zero;
    for (var i = 0; i < 10000; i++) {
      final key = generateRandomBytes(16);
      final iv = generateRandomBytes(16);
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

  test('random encrypt test', () {
    final random = Random.secure();
    for (var start = 0; start < 10; start++) {
      debugPrint('random encrypt test: $start');
      final key = generateRandomBytes(16);
      final iv = generateRandomBytes(16);

      final hMacKey = generateRandomBytes();

      final encryptor = AesCryptor(encrypt: true, key: key, iv: iv);
      final decryptor = AesCryptor(encrypt: false, key: key, iv: iv);

      final sourceHMac = HMacSha256(hMacKey);
      final targetHMac = HMacSha256(hMacKey);

      for (var i = 0; i < 500; i++) {
        final source = generateRandomBytes(random.nextInt(1024));
        sourceHMac.update(source);
        final decrypted = decryptor.update(encryptor.update(source));
        targetHMac.update(decrypted);
      }

      targetHMac.update(decryptor.update(encryptor.finalize()));
      targetHMac.update(decryptor.finalize());

      final sourceResult = sourceHMac.finalize();
      final targetResult = targetHMac.finalize();
      expect(base64Encode(sourceResult), base64Encode(targetResult));
    }
  });
}
