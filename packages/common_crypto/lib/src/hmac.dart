import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'common_crypto_bindings_generated.dart';
import 'tools.dart';

const _kDigestDataCount = 32;

class HMacSha256 implements Finalizable {
  static Uint8List hmacSha256({
    required Uint8List key,
    required Uint8List data,
  }) {
    final hmac = HMacSha256(key);
    hmac.update(data);
    final result = hmac.finalize();
    hmac.dispose();
    return result;
  }

  final Uint8List key;

  final context = malloc<CCHmacContext>();

  HMacSha256(this.key) {
    final keyRef = key.pointer;
    bindings.CCHmacInit(context, kCCHmacAlgSHA256, keyRef.cast(), key.length);
    malloc.free(keyRef);
  }

  void update(Uint8List data) {
    final dataRef = data.pointer;
    bindings.CCHmacUpdate(context, dataRef.cast(), data.length);
    malloc.free(dataRef);
  }

  Uint8List finalize() {
    final digest = malloc<Uint8>(_kDigestDataCount);
    bindings.CCHmacFinal(context, digest.cast());
    final result = Uint8List.fromList(digest.asTypedList(_kDigestDataCount));
    malloc.free(digest);
    return result;
  }

  void dispose() {
    malloc.free(context);
  }
}
