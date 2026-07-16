import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';

import 'debug_logger.dart';

final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up the global listener before init so queued events are delivered.
  DesktopDrop.instance.addRawDropEventListener((event) async {
    if (event is DropDoneEvent && event.files.isNotEmpty) {
      logDropEvent(event, source: 'Main/GlobalListener');
      // Dock/Finder open events arrive without prior hover; location defaults to Offset.zero.
      final fromDockOrFinder = event.location == Offset.zero;

      if (fromDockOrFinder) {
        final names = event.files.map((e) => e.path.split('/').last).join("\n");
        // Show notification after first frame to ensure context is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _scaffoldMessengerKey.currentContext;
          if (ctx != null) {
            _scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text('Dock/Finder drop opened:\n$names'),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        });
      }
    }
  });
  // Initialize channel and signal readiness
  DesktopDrop.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  void loadFile(BuildContext context, bool bookmarkEnable) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString("apple-bookmark");
    if (jsonStr == null) return;
    debugPrint(jsonStr);
    Map<String, dynamic> data = json.decode(jsonStr);
    String path = data["path"]! as String;
    String appleBookmarkStr = data["apple-bookmark"]! as String;
    Uint8List appleBookmark = base64.decode(appleBookmarkStr);

    try {
      if (bookmarkEnable) {
        bool grantedPermission = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: appleBookmark);

        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text("file permission :$grantedPermission")),
        );
      }

      var file = File(path);
      var contents = await file.readAsBytes();
      var fileSize = contents.length;

      if (bookmarkEnable) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: appleBookmark,
        );
      }

      final snackBar = SnackBar(content: Text('file size:$fileSize'));
      _scaffoldMessengerKey.currentState?.showSnackBar(snackBar);
    } catch (e) {
      final snackBar = SnackBar(content: Text('error:$e'));
      _scaffoldMessengerKey.currentState?.showSnackBar(snackBar);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(title: const Text('Desktop Drop Example')),
        body: Wrap(
          direction: Axis.horizontal,
          runSpacing: 8,
          spacing: 8,
          children: [
            const TextDropDemo(),
            const ExampleDragTarget(catchAppWideDrops: true),
            const ExampleDragTarget(catchAppWideDrops: false),
            const ExampleDragTarget(catchAppWideDrops: false),
            const ExampleDragTarget(catchAppWideDrops: false),
            const ExampleDragTarget(catchAppWideDrops: false),
            const ExampleDragTarget(catchAppWideDrops: false),
            if (UniversalPlatform.isMacOS)
              StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      const Text(
                        "Test Apple Bookmark\n1 drag file \n2 save the bookmark,\n3 restart app\n4 choice test button",
                      ),
                      TextButton(
                        onPressed: () async {
                          loadFile(context, true);
                          return;
                        },
                        child: const Text("with applemark, suc"),
                      ),
                      TextButton(
                        onPressed: () async {
                          loadFile(context, false);
                          return;
                        },
                        child: const Text("without applemark, err"),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class TextDropDemo extends StatefulWidget {
  const TextDropDemo({super.key});

  @override
  State<TextDropDemo> createState() => _TextDropDemoState();
}

class _TextDropDemoState extends State<TextDropDemo> {
  String? _lastText;
  String? _lastLabel;

  Future<void> _handleDrop(List<DropItem> items) async {
    for (final item in items) {
      if (!item.isMemoryBacked || !item.isTextLike) continue;

      final uris = await item.readAsUris();
      final text = uris.isNotEmpty
          ? uris.map((uri) => uri.toString()).join('\n')
          : await item.readAsText();
      if (text == null || !mounted) return;

      setState(() {
        _lastText = text.length > 2000 ? '${text.substring(0, 2000)}...' : text;
        _lastLabel = item.name;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      catchAppWideDrops: true,
      onDragDone: (details) {
        logDropDetails(details, source: 'TabShell/DropTarget');
        _handleDrop(details.files);
      },
      child: Container(
        height: 200,
        width: 300,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          border: Border.all(color: Colors.green.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _lastText == null
            ? const Center(child: Text('Drop text or links here'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastLabel ?? 'Text',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(_lastText!),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ExampleDragTarget extends StatefulWidget {
  const ExampleDragTarget({super.key, this.catchAppWideDrops = false});

  final bool catchAppWideDrops;

  @override
  State<ExampleDragTarget> createState() => _ExampleDragTargetState();
}

class _ExampleDragTargetState extends State<ExampleDragTarget> {
  final List<XFile> _list = [];
  final List<DropItem> dropFiles = [];

  bool _dragging = false;
  Offset? offset;

  Future<void> printFiles(List<DropItem> files, [int depth = 0]) async {
    for (final file in files) {
      if (file is DropItemDirectory) {
        printFiles(file.children, depth + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      catchAppWideDrops: widget.catchAppWideDrops,
      onDragDone: (detail) async {
        setState(() {
          _list.addAll(detail.files);
          dropFiles.addAll(detail.files);
        });
        await printFiles(detail.files);
      },
      onDragUpdated: (details) {
        setState(() {
          offset = details.localPosition;
        });
      },
      onDragEntered: (detail) {
        setState(() {
          _dragging = true;
          offset = detail.localPosition;
        });
      },
      onDragExited: (detail) {
        setState(() {
          _dragging = false;
          offset = null;
        });
      },
      child: Container(
        height: 200,
        width: 200,
        color: _dragging ? Colors.blue.withValues(alpha: 0.4) : Colors.black26,
        child: Stack(
          children: [
            if (_list.isEmpty)
              const Center(child: Text("Drop here"))
            else
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _list.map((e) => e.path.split('/').last).join("\n"),
                  style: const TextStyle(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (widget.catchAppWideDrops)
              const Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'Primary (catches Dock)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (offset != null)
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  '$offset',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_list.isNotEmpty && UniversalPlatform.isMacOS)
              Align(
                alignment: Alignment.bottomRight,
                child: TextButton(
                  onPressed: () async {
                    if (dropFiles.isEmpty) return;

                    Map<String, String> data = {};
                    data["path"] = dropFiles[0].path;

                    if (dropFiles[0].extraAppleBookmark != null) {
                      String bookmark = base64.encode(
                        dropFiles[0].extraAppleBookmark!,
                      );
                      data["apple-bookmark"] = bookmark;
                    }

                    String jsonStr = json.encode(data);
                    debugPrint(jsonStr);
                    final SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    prefs.setString("apple-bookmark", jsonStr);

                    _scaffoldMessengerKey.currentState?.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Save Suc, restart app, and Test Apple Bookmark',
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'save bookmark',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
