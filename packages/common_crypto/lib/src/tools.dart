import 'dart:ffi';
import 'dart:io';

import 'common_crypto_bindings_generated.dart';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final CommonCryptoBindings bindings = CommonCryptoBindings(_dylib);
