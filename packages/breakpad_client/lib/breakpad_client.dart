import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'breakpad_client_bindings_generated.dart';

/// A very short-lived native function.
///
/// For very short-lived functions, it is fine to call them on the main isolate.
/// They will block the Dart execution while running the native function, so
/// only do this for native functions which are guaranteed to be short-lived.
void init_exception_handle(String dir) =>
    _bindings.init_breakpad_exception_handler(dir.toNativeUtf8().cast());

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
