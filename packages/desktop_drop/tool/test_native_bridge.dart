import 'dart:io';

/// Compile and exercise the shared C++ bridge without a Flutter window.
/// macOS/Linux: dart run tool/test_native_bridge.dart
Future<void> main() async {
  final root = Platform.script.resolve('../').toFilePath();
  final bridge = '${root}macos/desktop_drop/Sources/desktop_drop_ffi';
  final temporary = await Directory.systemTemp.createTemp(
    'desktop_drop_bridge_',
  );
  Future<void> run(String command, List<String> args) async {
    final process = await Process.run(command, args, workingDirectory: root);
    stdout.write(process.stdout);
    stderr.write(process.stderr);
    if (process.exitCode != 0) {
      throw ProcessException(
        command,
        args,
        'Native bridge test failed',
        process.exitCode,
      );
    }
  }

  try {
    final loader = '${temporary.path}/dart_api_dl.o';
    final executable = '${temporary.path}/bridge_test';
    final otherLoader = '${temporary.path}/other_plugin_loader.o';
    await run('cc', ['-c', '$bridge/dart_bridge_api.c', '-o', loader]);
    // Link a second plugin's SDK loader to catch global-symbol collisions.
    await run('cc', ['-c', '$bridge/vendor/dart_api_dl.c', '-o', otherLoader]);
    await run('c++', [
      '-std=c++17',
      '-pthread',
      '-Wall',
      '-Wextra',
      '-Werror',
      '-I$bridge/include',
      '-I$bridge/vendor',
      '$bridge/desktop_drop_ffi.cc',
      '${root}test/native/bridge_test.cc',
      loader,
      otherLoader,
      '-o',
      executable,
    ]);
    await run(executable, []);
  } finally {
    await temporary.delete(recursive: true);
  }
}
