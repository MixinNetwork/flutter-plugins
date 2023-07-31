import 'dart:io';

import 'log_file_manager.dart';
import 'write_log_to_file_ffi.dart' as ffi;

bool enableLogColor = !Platform.isIOS;

void writeLog(String log) {
  if (Platform.isMacOS) {
    ffi.writeLog(log);
    return;
  }
  LogFileManager.instance?.write(log);
}

Future<void> initLogger(
  String logDir,
  int maxFileCount,
  int maxFileLength,
  String? fileLeading,
) async {
  if (Platform.isMacOS) {
    ffi.initLogger(logDir, maxFileCount, maxFileLength, fileLeading);
    return;
  }
  await LogFileManager.init(
    logDir,
    maxFileCount,
    maxFileLength,
    fileLeading: fileLeading,
  );
}

void setLoggerFileLeading(String? fileLeading) {
  assert(LogFileManager.instance != null, 'Logger is not initialized');
  LogFileManager.instance?.setLoggerFileLeading(fileLeading);
}
