import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'mixin_logger_bindings_generated.dart';
import 'write_to_file.dart';

const String _libName = 'mixin_logger';

/// The dynamic library in which the symbols for [MixinLoggerBindings] can be found.
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

class _WriteToFileNone implements WriteToFileImpl {
  @override
  bool get enableLogColor => true;

  @override
  void init(String logDir, int maxFileCount, int maxFileLength,
      String? fileLeading) {}

  @override
  void setLoggerFileLeading(String? fileLeading) {}

  @override
  void writeLog(String log) {}
}

class WriteToFileImpl extends WriteToFile {
  WriteToFileImpl._();

  factory WriteToFileImpl() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return _WriteToFileNone();
    }
    return WriteToFileImpl._();
  }

  @override
  void init(
    String logDir,
    int maxFileCount,
    int maxFileLength,
    String? fileLeading,
  ) {
    final dir = logDir.toNativeUtf8();
    final fileLeadingPtr = (fileLeading ?? "").toNativeUtf8();
    _bindings.mixin_logger_init(
      dir.cast(),
      maxFileLength,
      maxFileCount,
      fileLeadingPtr.cast(),
    );
    malloc.free(dir);
    malloc.free(fileLeadingPtr);
  }

  @override
  void setLoggerFileLeading(String? fileLeading) {
    final fileLeadingPtr = (fileLeading ?? "").toNativeUtf8();
    _bindings.mixin_logger_set_file_leading(fileLeadingPtr.cast());
    malloc.free(fileLeadingPtr);
  }

  @override
  void writeLog(String log) {
    final str = log.toNativeUtf8();
    _bindings.mixin_logger_write_log(str.cast());
    malloc.free(str);
  }

  @override
  bool get enableLogColor => !Platform.isIOS;
}
