abstract class WriteToFile {
  void init(
    String logDir,
    int maxFileCount,
    int maxFileLength,
    String? fileLeading,
  );

  void setLoggerFileLeading(String? fileLeading);

  void writeLog(String log);

  bool get enableLogColor;
}
