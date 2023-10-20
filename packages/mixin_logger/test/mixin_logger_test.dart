import 'package:ansicolor/ansicolor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_logger/mixin_logger.dart';

void main() {
  test('test logger colors', () async {
    ansiColorDisabled = false;
    v('verbose message');
    d('debug message');
    i('info message');
    w('warning message');
    e('error message', "Error", StackTrace.current);
    wtf('wtf message');
  });
}
