import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'breakpad_client_bindings_generated.dart';

void initExceptionHandle(String dir) =>
    _bindings.breakpad_client_init_exception_handler(dir.toNativeUtf8().cast());

void setLogger(void Function(String log) logger) {
  void callback(Pointer<Char> cstr) {
    final log = cstr.cast<Utf8>().toDartString();
    logger(log);
  }

  _bindings.breakpad_client_set_logger(
      NativeCallable<Void Function(Pointer<Char>)>.listener(callback)
          .nativeFunction);
}

const String _libName = 'breakpad_client';

/// The dynamic library in which the symbols for [BreakpadClientBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final BreakpadClientBindings _bindings = BreakpadClientBindings(_dylib);
