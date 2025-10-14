import 'package:web/web.dart' as web;

class DesktopDropWebFile {
  DesktopDropWebFile._internal();

  static final DesktopDropWebFile _instance = DesktopDropWebFile._internal();

  factory DesktopDropWebFile() => _instance;

  final Map<String, web.File> webFileMap = {};

  web.File? getWebFile(String path) {
    return webFileMap[path];
  }
}
