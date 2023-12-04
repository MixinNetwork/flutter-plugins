import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:common_crypto/src/hmac.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'aes_test.dart';

void main() {
  test('hmac 256 test', () {
    final key = base64Decode('Y9hRHsqr9adyX29DYsjWhg==');
    final data = Uint8List.fromList(utf8.encode('Mixin'));
    final result = HMacSha256.hmacSha256(key: key, data: data);
    expect(
      base64Encode(result),
      equals('Zg/Z5GkXYHKPR/uPVOe4Z5ZPzSgRoDL72mrm5/TyCrQ='),
    );
  });

  test('random generate hmac', () {
    final random = Random.secure();
    for (var start = 0; start < 10; start++) {
      final hMacKey = generateRandomBytes();
      final commonCryptoHMac = HMacSha256(hMacKey);
      final pointyHMac = HMac(SHA256Digest(), 64)..init(KeyParameter(hMacKey));

      final data = random.nextInt(1024);
      for (var i = 0; i < data; i++) {
        final bytes = generateRandomBytes(random.nextInt(1024));
        commonCryptoHMac.update(bytes);
        pointyHMac.update(bytes, 0, bytes.length);
      }

      final commonCryptoResult = commonCryptoHMac.finalize();
      final bytes = Uint8List(pointyHMac.macSize);
      final len = pointyHMac.doFinal(bytes, 0);
      final pointyResult = bytes.sublist(0, len);

      debugPrint('commonCryptoResult: ${base64Encode(commonCryptoResult)} '
          'pointyResult: ${base64Encode(pointyResult)}');
      expect(commonCryptoResult, equals(pointyResult));
    }
  });
}
