import 'dart:io';

import 'log_file_manager.dart';

bool enableLogColor = !Platform.isIOS;

void writeLog(String log) {
  LogFileManager.instance?.write(log);
}

Future<void> initLogger(
  String logDir,
  int maxFileCount,
  int maxFileLength,
  String? fileLeading,
) async {
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
