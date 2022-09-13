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
) async {
  await LogFileManager.init(logDir, maxFileCount, maxFileLength);
}
