import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'mixin_logger_bindings_generated.dart';

const String _libName = 'mixin_logger';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.process();
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
final MixinLoggerBindings _bindings = MixinLoggerBindings(_dylib);

void writeLog(String log) {
  final str = log.toNativeUtf8();
  _bindings.MixinLoggerWriteLog(str.cast());
  malloc.free(str);
}

Future<void> initLogger(
  String logDir,
  int maxFileCount,
  int maxFileLength,
  String? fileLeading,
) async {
  final dir = logDir.toNativeUtf8();
  final fileLeadingPtr = (fileLeading ?? "").toNativeUtf8();
  _bindings.MixinLoggerInit(
    dir.cast(),
    maxFileLength,
    maxFileCount,
    fileLeadingPtr.cast(),
  );
  malloc.free(dir);
  malloc.free(fileLeadingPtr);
}

void setLoggerFileLeading(String? fileLeading) {
  final fileLeadingPtr = (fileLeading ?? "").toNativeUtf8();
  _bindings.MixinLoggerSetFileLeading(fileLeadingPtr.cast());
  malloc.free(fileLeadingPtr);
}
