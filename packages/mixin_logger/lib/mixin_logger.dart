library mixin_logger;

import 'package:ansicolor/ansicolor.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'src/write_log_to_file_web.dart'
    if (dart.library.io) 'src/write_log_to_file_io.dart' as platform;

const kLogMode = !kReleaseMode;

enum _LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  wtf,
}

final _verbosePen = AnsiPen()..gray();
final _debugPen = AnsiPen()..blue();
final _infoPen = AnsiPen()..green();
final _warningPen = AnsiPen()..yellow();
final _errorPen = AnsiPen()..red();
final _wtfPen = AnsiPen()..magenta();

extension _LogLevelExtension on _LogLevel {
  String get prefix {
    switch (this) {
      case _LogLevel.verbose:
        return '[V]';
      case _LogLevel.debug:
        return '[D]';
      case _LogLevel.info:
        return '[I]';
      case _LogLevel.warning:
        return '[W]';
      case _LogLevel.error:
        return '[E]';
      case _LogLevel.wtf:
        return '[WTF]';
    }
  }

  String colorize(String message) {
    if (!platform.enableLogColor) {
      return message;
    }
    switch (this) {
      case _LogLevel.verbose:
        return _verbosePen(message);
      case _LogLevel.debug:
        return _debugPen(message);
      case _LogLevel.info:
        return _infoPen(message);
      case _LogLevel.warning:
        return _warningPen(message);
      case _LogLevel.error:
        return _errorPen(message);
      case _LogLevel.wtf:
        return _wtfPen(message);
    }
  }
}

void initLogger(
  String logDir, {
  int maxFileCount = 10,
  int maxFileLength = 1024 * 1024 * 10, // 10 MB
}) {
  assert(maxFileCount > 1, 'maxFileCount must be greater than 1');
  assert(maxFileLength > 10 * 1024, 'maxFileLength must be greater than 10 KB');
  platform.initLogger(logDir, maxFileCount, maxFileLength);
}

void v(String message) {
  _print(message, _LogLevel.verbose);
}

void d(String message) {
  _print(message, _LogLevel.debug);
}

void i(String message) {
  _print(message, _LogLevel.info);
}

void w(String message) {
  _print(message, _LogLevel.warning);
}

void e(String message) {
  _print(message, _LogLevel.error);
}

void wtf(String message) {
  _print(message, _LogLevel.wtf);
}

void _print(String message, _LogLevel level) {
  final logToFile = kLogMode || level.index > _LogLevel.debug.index;
  if (logToFile && !kIsWeb) {
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(now);
    platform.writeLog('$date ${level.prefix} $message');
  }
  if (!kLogMode) return;
  // ignore: avoid_print
  print(level.colorize('${level.prefix} $message'));
}
