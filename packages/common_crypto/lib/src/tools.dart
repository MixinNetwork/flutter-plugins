import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'common_crypto_bindings_generated.dart';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final CommonCryptoBindings bindings = CommonCryptoBindings(_dylib);

extension Uint8ListPointer on Uint8List {
  Pointer<Uint8> get pointer {
    final pointer = malloc<Uint8>(length);
    final data = pointer.asTypedList(length);
    data.setAll(0, this);
    return pointer;
  }
}
