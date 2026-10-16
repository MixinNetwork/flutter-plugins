import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'common/app_theme.dart';
import 'common/received_item.dart';
import 'pages/drop_content.dart';
import 'pages/drop_stage.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Desktop Drop',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    home: const DropPlayground(),
  );
}

class DropPlayground extends StatefulWidget {
  const DropPlayground({super.key});

  @override
  State<DropPlayground> createState() => _DropPlaygroundState();
}

class _DropPlaygroundState extends State<DropPlayground> {
  DropDetails? _drop;
  String? _receiver;
  Map<DropItem, ReceivedItem> _content = {};
  double _stageFraction = .38;

  Future<void> _received(String target, DropDetails event) async {
    setState(() {
      _drop = event;
      _receiver = target;
      _content = {};
    });
    final content = await readDrop(
      event,
      onDirectoryAccessRequired: (directory) async {
        if (!mounted || !identical(_drop, event)) return false;
        final authorize = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Directory access required'),
            content: Text(
              'Android has not granted access to the children of "${directory.name}". Authorize this folder to read its contents.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Authorize folder'),
              ),
            ],
          ),
        );
        if (authorize != true || !mounted || !identical(_drop, event)) {
          return false;
        }
        await DesktopDrop.instance.requestDirectoryAccess(directory: directory);
        return mounted && identical(_drop, event);
      },
    );
    if (mounted && identical(_drop, event)) {
      setState(() => _content = content);
    }
    final failures = content.values.where((item) => item.error != null);
    if (failures.isNotEmpty) {
      throw StateError(
        'Could not receive ${failures.length} items: ${failures.first.error}',
      );
    }
  }

  void _clear() {
    setState(() {
      _drop = null;
      _receiver = null;
      _content = {};
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.move_to_inbox_outlined,
                  size: 22,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Desktop Drop',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  kIsWeb ? 'Web' : defaultTargetPlatform.name,
                  style: const TextStyle(color: AppTheme.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Keep both panes visible on desktop. Very small hosts can pan
                // horizontally rather than moving results below the targets.
                final width = math.max(800.0, constraints.maxWidth);
                final left = (width * _stageFraction).clamp(300.0, width - 460);
                final panes = SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: left,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                          child: DropStage(onDrop: _received),
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (details) => setState(
                            () => _stageFraction =
                                ((left + details.delta.dx) / width).clamp(
                                  .28,
                                  .52,
                                ),
                          ),
                          child: const SizedBox(
                            width: 12,
                            child: Center(
                              child: SizedBox(
                                width: 1,
                                height: double.infinity,
                                child: ColoredBox(color: AppTheme.border),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 18, 20, 18),
                          child: DropContent(
                            key: ObjectKey(_drop),
                            event: _drop,
                            content: _content,
                            receiver: _receiver,
                            onClear: _clear,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                return constraints.maxWidth < width
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: panes,
                      )
                    : panes;
              },
            ),
          ),
        ],
      ),
    ),
  );
}
