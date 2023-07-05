import 'dart:convert';
import 'dart:typed_data';

import 'package:common_crypto/src/hmac.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
