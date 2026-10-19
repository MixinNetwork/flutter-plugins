import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'breakpad_client_bindings_generated.dart';

void initExceptionHandle(String dir) =>
    using((arena) => _bindings.breakpad_client_init_exception_handler(
        dir.toNativeUtf8(allocator: arena).cast()));

NativeCallable<Void Function(Pointer<Char>)>? _logger;

void setLogger(void Function(String log) logger) {
  void callback(Pointer<Char> cstr) {
    final log = cstr.cast<Utf8>().toDartString();
    malloc.free(cstr);
    logger(log);
  }

  final previous = _logger;
  _logger = NativeCallable<Void Function(Pointer<Char>)>.listener(callback);
  _bindings.breakpad_client_set_logger(_logger!.nativeFunction);
  previous?.close();
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
