import 'write_to_file.dart';

class WriteToFileImpl extends WriteToFile {
  WriteToFileImpl();

  @override
  void init(String logDir, int maxFileCount, int maxFileLength,
      String? fileLeading) {}

  @override
  void setLoggerFileLeading(String? fileLeading) {}

  @override
  void writeLog(String log) {}

  @override
  bool get enableLogColor => false;
}
