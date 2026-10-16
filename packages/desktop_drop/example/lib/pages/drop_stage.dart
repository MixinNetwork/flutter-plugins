import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../common/app_theme.dart';

enum _Rule {
  any('Any content'),
  files('Files'),
  folders('Folders'),
  text('Text'),
  urls('URLs'),
  plainText('Plain text files'),
  png('PNG files');

  const _Rule(this.label);
  final String label;

  bool accepts(DragDetails details) {
    final entries = details.items
        .where((item) => item.kind != DropItemKind.string)
        .toList();
    return switch (this) {
      urls => details.items.any((item) => item.mimeType == 'text/uri-list'),
      plainText || png =>
        entries.isNotEmpty &&
            entries.every(
              (item) =>
                  item.kind == DropItemKind.file &&
                  item.mimeType ==
                      (this == plainText ? 'text/plain' : 'image/png'),
            ),
      _ => true,
    };
  }
}

class DropStage extends StatefulWidget {
  const DropStage({super.key, required this.onDrop});
  final FutureOr<void> Function(String target, DropDetails event) onDrop;

  @override
  State<DropStage> createState() => _DropStageState();
}

class _DropStageState extends State<DropStage> {
  final _enabled = [true, true, true];
  final _rules = [_Rule.any, _Rule.plainText, _Rule.png];
  static const _names = ['Parent', 'Child A', 'Child B'];
  DropOperation _operation = DropOperation.copy;
  int _front = 2;
  int? _hovering;
  DragDetails? _preview;

  // Only rebuild when the feedback shown by this example changes.
  void _hover(int index, DragDetails details) {
    if (_hovering == index && listEquals(_preview?.items, details.items)) {
      return;
    }
    setState(() {
      _hovering = index;
      _preview = details;
    });
  }

  Widget _target(int index, Widget child) => DropTarget(
    key: ValueKey('target-${_names[index]}'),
    behavior: HitTestBehavior.opaque,
    enabled: _enabled[index],
    operation: _operation,
    acceptedKinds: switch (_rules[index]) {
      _Rule.files || _Rule.plainText || _Rule.png => const {DropItemKind.file},
      _Rule.text || _Rule.urls => const {DropItemKind.string},
      _Rule.folders => const {DropItemKind.directory},
      _ => const {
        DropItemKind.file,
        DropItemKind.directory,
        DropItemKind.string,
      },
    },
    onWillAccept: switch (_rules[index]) {
      _Rule.plainText || _Rule.png || _Rule.urls => _rules[index].accepts,
      _ => null,
    },
    onEnter: (details) => _hover(index, details),
    onMove: (details) => _hover(index, details),
    onLeave: () {
      if (_hovering == index) {
        setState(() {
          _hovering = null;
          _preview = null;
        });
      }
    },
    onDrop: (details) => widget.onDrop(_names[index], details),
    child: child,
  );

  Widget _controls(int index) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              _names[index],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch(
              key: ValueKey('toggle-${_names[index]}'),
              value: _enabled[index],
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => setState(() => _enabled[index] = value),
            ),
          ),
        ],
      ),
      DropdownButtonHideUnderline(
        child: DropdownButton<_Rule>(
          key: ValueKey('rule-${_names[index]}'),
          value: _rules[index],
          isExpanded: true,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          items: [
            for (final rule in _Rule.values)
              DropdownMenuItem(value: rule, child: Text(rule.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _rules[index] = value);
          },
        ),
      ),
    ],
  );

  Widget _child(int index) {
    final active = _hovering == index;
    final tint = index == 1 ? const Color(0xFFEEF3FF) : const Color(0xFFF1EEF9);
    return _target(
      index,
      AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: !_enabled[index]
              ? const Color(0xFFF0F1F3)
              : active
              ? Color.lerp(tint, AppTheme.accent, .10)
              : tint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? AppTheme.accent
                : index == 1
                ? const Color(0xFFCBD8F5)
                : const Color(0xFFD8CFF0),
            width: active ? 2 : 1,
          ),
          boxShadow: index == _front
              ? [
                  const BoxShadow(
                    color: Color(0x100F172A),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _controls(index),
            Expanded(
              child: Center(
                child: Text(
                  !_enabled[index]
                      ? 'Disabled'
                      : active
                      ? 'Release to drop'
                      : 'Drop here',
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? AppTheme.accent : AppTheme.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 36,
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Drop area',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const Text('Action ', style: TextStyle(fontSize: 12)),
            DropdownButtonHideUnderline(
              child: DropdownButton<DropOperation>(
                key: const ValueKey('operation'),
                value: _operation,
                isDense: true,
                style: const TextStyle(fontSize: 12, color: AppTheme.ink),
                items: [
                  for (final operation in DropOperation.values)
                    DropdownMenuItem(
                      value: operation,
                      child: Text(operation.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _operation = value);
                },
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _target(
          0,
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hovering == 0
                  ? AppTheme.accentLight
                  : const Color(0xFFF0F2F6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovering == 0 ? AppTheme.accent : AppTheme.border,
                width: _hovering == 0 ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _controls(0),
                const SizedBox(height: 20),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Opaque siblings overlap in the same Stack. A rejecting front
                      // target falls back to Parent, never to the obscured sibling.
                      final width = constraints.maxWidth * .80;
                      final height = constraints.maxHeight * .65;
                      Widget positioned(int index) => Positioned(
                        key: ValueKey('layer-$index'),
                        left: index == 1 ? 0 : null,
                        right: index == 2 ? 0 : null,
                        top: index == 1 ? 0 : null,
                        bottom: index == 2 ? 0 : null,
                        width: width,
                        height: height,
                        child: _child(index),
                      );
                      return Stack(
                        children: [
                          positioned(_front == 1 ? 2 : 1),
                          positioned(_front),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _hovering == 0
                      ? 'Release to drop on Parent'
                      : 'Drop on the background for Parent',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              '${_names[_front]} is in front',
              style: const TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('swap-layers'),
            onPressed: () => setState(() => _front = _front == 1 ? 2 : 1),
            icon: const Icon(Icons.swap_vert, size: 16),
            label: const Text('Swap layers', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      SizedBox(
        height: 34,
        child: Text(
          _preview == null
              ? 'Files, folders, text or links. Contents are read on request.'
              : '${_names[_hovering!]} · ${_operation.name}\nPreview: ${_preview!.items.map((item) => item.kind.name).toSet().join(', ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppTheme.muted),
        ),
      ),
    ],
  );
}
