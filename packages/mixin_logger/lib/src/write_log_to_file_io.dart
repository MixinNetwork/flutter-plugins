import 'dart:io';

import 'log_file_manager.dart';

bool enableLogColor = !Platform.isIOS;

void writeLog(String log) {
  LogFileManager.instance?.write(log);
}

void initLogger(
  String logDir,
  int maxFileCount,
  int maxFileLength,
) {
  LogFileManager.init(logDir, maxFileCount, maxFileLength);
}
