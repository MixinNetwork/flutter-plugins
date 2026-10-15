import 'dart:io';

import 'package:ffigen/ffigen.dart';

/// Run `dart run tool/ffigen.dart` after changing the bridge's C header.
Future<void> main() async {
  final root = Platform.script.resolve('../');
  await FfiGenerator(
    input: Input(
      entryPoints: [
        root.resolve(
          'macos/desktop_drop/Sources/desktop_drop_ffi/include/desktop_drop_ffi.h',
        ),
      ],
    ),
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
          }.contains(node.originalName);
        },
        struct: (node) => node.isIncluded = node.originalName == 'DDRequest',
        typealias: (node) {
          if (node.originalName.startsWith('DDDecide')) {
            node.isIncluded = TypealiasInclude.always;
          }
        },
      ),
    ],
  ).generate();
}
