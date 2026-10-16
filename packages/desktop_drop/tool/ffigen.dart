import 'dart:io';

import 'package:ffigen/ffigen.dart';

/// Run `dart run tool/ffigen.dart` after changing the bridge's C header.
Future<void> main() async {
  final root = Platform.script.resolve('../');
  await FfiGenerator(
    input: Input(entryPoints: [root.resolve('src/desktop_drop_ffi.h')]),
    output: Output(
      dart: DartOutput(path: root.resolve('lib/src/bridge_bindings.g.dart')),
      style: const DynamicLibraryBindings(wrapperName: 'DropBridgeBindings'),
      preamble:
          '// Generated from desktop_drop_ffi.h. Do not edit.\n'
          '// Regenerate with: dart run tool/ffigen.dart\n',
    ),
    visitors: [
      Visitor(
        func: (node) {
          node.isIncluded = const {
            'dd_bridge_register',
            'dd_bridge_complete',
            'dd_bridge_unregister',
            'dd_rpc_open',
            'dd_rpc_call',
            'dd_rpc_complete',
            'dd_alloc',
            'dd_free',
          }.contains(node.originalName);
        },
        struct: (node) => node.isIncluded = const {
          'DDRequest',
          'DDDecision',
        }.contains(node.originalName),
        typealias: (node) {
          if (node.originalName.startsWith('DDDecide')) {
            node.isIncluded = TypealiasInclude.always;
          }
        },
      ),
    ],
  ).generate();
  // CocoaPods copies public headers into the framework. Keep its standalone
  // module header generated from the same ABI used by Dart and native callers.
  final header = await File.fromUri(root.resolve('src/desktop_drop_ffi.h'))
      .readAsString();
  await File.fromUri(
    root.resolve(
      'darwin/desktop_drop/Sources/desktop_drop_ffi/include/desktop_drop_ffi.h',
    ),
  ).writeAsString(
    '// Generated from src/desktop_drop_ffi.h. Do not edit.\n'
    '// Regenerate with: dart run tool/ffigen.dart\n\n$header',
  );
}
