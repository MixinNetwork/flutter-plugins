import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarkTools extends StatefulWidget {
  const BookmarkTools({super.key, this.file});
  final DropFileItem? file;

  @override
  State<BookmarkTools> createState() => _BookmarkToolsState();
}

class _BookmarkToolsState extends State<BookmarkTools> {
  (String, Uint8List)? _saved;
  String? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(
        'apple-bookmark',
      );
      if (value == null) return;
      final data = jsonDecode(value) as Map;
      if (mounted) {
        setState(
          () => _saved = (
            data['path'] as String,
            base64Decode(data['apple-bookmark'] as String),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    }
  }

  Future<void> _save() async {
    final file = widget.file!;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'apple-bookmark',
        jsonEncode({
          'path': file.localPath,
          'apple-bookmark': base64Encode(file.appleBookmark!),
        }),
      );
      if (mounted) {
        setState(() {
          _saved = (file.localPath!, file.appleBookmark!);
          _result = 'Bookmark saved.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    }
  }

  Future<void> _read(bool withAccess) async {
    final saved = _saved!;
    setState(() {
      _busy = true;
      _result = null;
    });
    var accessed = false;
    try {
      if (withAccess) {
        accessed = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: saved.$2);
        if (!accessed) throw StateError('macOS denied security-scoped access');
      }
      final file = XFile.fileSystem(path: saved.$1);
      final bytes = await file
          .openRead(0, 64)
          .expand((chunk) => chunk)
          .toList();
      if (mounted) {
        setState(() => _result = 'Read ${bytes.length} bytes successfully.');
      }
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    } finally {
      if (accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: saved.$2,
          );
        } catch (error) {
          debugPrint('Cannot stop bookmark access: $error');
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.file?.appleBookmark != null && widget.file?.localPath != null)
        TextButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.bookmark_add_outlined, size: 16),
          label: const Text('Save bookmark'),
        ),
      SelectableText(
        _saved?.$1 ?? 'No bookmark saved.',
        style: const TextStyle(fontSize: 12),
      ),
      if (_saved != null)
        Wrap(
          spacing: 6,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _read(true),
              child: const Text('Read with access'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _read(false),
              child: const Text('Read without access'),
            ),
          ],
        ),
      if (_result != null)
        SelectableText(_result!, style: const TextStyle(fontSize: 12)),
    ],
  );
}
