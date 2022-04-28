import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

final context = p.Context(style: p.Style.windows);

Future<void> collect() async {
  final executable = await _getDumpExecutable();

  const windowsBuildDir = r'build\windows';

  const outputPath = r'build\syms';

  final plugins = Directory(context.join(windowsBuildDir, 'plugins'))
      .listSync()
      .whereType<Directory>();

  Future<void> _dumpToFile(String pdbPath, String dumpName) async {
    try {
      final ret = await _dump(executable, pdbPath);
      final file = File(context.join(outputPath, '$dumpName.sym'));
      if (file.existsSync()) {
        file.deleteSync();
      }
      file.createSync(recursive: true);
      file.writeAsStringSync(ret);
    } catch (error) {
      print('Error while dumping $pdbPath $error');
    }
  }

  for (final plugin in plugins) {
    // normal plugin
    var pdbPath = context.join(
        plugin.path, 'Release', '${p.basename(plugin.path)}_plugin.pdb');

    if (!File(pdbPath).existsSync()) {
      // ffi plugin
      pdbPath = context.join(
          plugin.path, 'shared', 'Release', '${p.basename(plugin.path)}.pdb');
    }
    final dumpName = context.basenameWithoutExtension(pdbPath);
    _dumpToFile(pdbPath, dumpName);
  }

}

Future<String> _dump(String executable, String pdb) async {
  final path = File(pdb).absolute.path;
  final result = await Process.run(executable, [path]);
  if (result.exitCode != 0) {
    throw Exception('Failed to dump $path ${result.stderr}');
  }
  return result.stdout;
}

Future<String> _getDumpExecutable() async {
  final config = await findPackageConfig(Directory.current);
  if (config == null) {
    throw Exception('Could not find package config');
  }
  final package =
      config.packages.firstWhere((e) => e.name == 'debug_info_collector');
  final path = package.packageUriRoot.toFilePath(windows: true);
  return p.join(path, 'assets', 'dump_syms.exe');
}
