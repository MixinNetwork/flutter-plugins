import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'drop_item.dart';
import 'events.dart';

abstract class RawDropListener {
  /// Returns true if event was handled, false otherwise
  bool handleDropEvent(DropEvent event);

  Offset globalToLocalOffset(Offset global);
}

class DesktopDrop {
  static const MethodChannel _channel = MethodChannel('desktop_drop');

  DesktopDrop._();

  static final instance = DesktopDrop._();

  var _initialized = false;

  RawDropListener? _currentTargetListener;
  Offset? _offset;

  void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler(
      (call) async {
        try {
          return await _handleMethodChannel(call);
        } catch (e, s) {
          debugPrint('_handleMethodChannel: $e $s');
        }
      },
    );
  }

  Future<void> _handleMethodChannel(MethodCall call) async {
    switch (call.method) {
      case "entered":
        final position = (call.arguments as List).cast<double>();
        _offset = Offset(position[0], position[1]);
        _notifyPositionEvent(DropEnterEvent(location: _offset!));
        break;
      case "updated":
        final position = (call.arguments as List).cast<double>();
        final previousOffset = _offset;
        _offset = Offset(position[0], position[1]);
        if (previousOffset == null) {
          _notifyPositionEvent(DropEnterEvent(location: _offset!));
        } else {
          _notifyPositionEvent(DropUpdateEvent(location: _offset!));
        }
        break;
      case "exited":
        _notifyPositionEvent(DropExitEvent(location: _offset ?? Offset.zero));
        _offset = null;
        break;
      case "performOperation":
        final paths = (call.arguments as List).cast<String>();
        _notifyDoneEvent(
          DropDoneEvent(
            location: _offset ?? Offset.zero,
            files: paths.map((e) => XFile(e)).toList(),
          ),
        );
        _offset = null;
        break;
      case "performOperation_linux":
        // gtk notify 'exit' before 'performOperation'.
        final text = (call.arguments as List<dynamic>)[0] as String;
        final offset = ((call.arguments as List<dynamic>)[1] as List<dynamic>).cast<double>();
        final paths = const LineSplitter().convert(text).map((e) {
          try {
            return Uri.tryParse(e)?.toFilePath() ?? '';
          } catch (error, stacktrace) {
            debugPrint('failed to parse linux path: $error $stacktrace');
          }
          return '';
        }).where((e) => e.isNotEmpty);
        _notifyDoneEvent(
          DropDoneEvent(
            location: Offset(offset[0], offset[1]),
            files: paths.map((e) => XFile(e)).toList(),
          ),
        );
        break;
      case "performOperation_web":
        final results = (call.arguments as List)
            .cast<Map>()
            .map((e) => WebDropItem.fromJson(e.cast<String, dynamic>()))
            .map((e) => XFile(
                  e.uri,
                  name: e.name,
                  length: e.size,
                  lastModified: e.lastModified,
                  mimeType: e.type,
                ))
            .toList();
        _notifyDoneEvent(
          DropDoneEvent(location: _offset ?? Offset.zero, files: results),
        );
        _offset = null;
        break;
      default:
        throw UnimplementedError('${call.method} not implement.');
    }
  }

  void _notifyPositionEvent(DropEvent event) {
    final RawDropListener? target;

    if (event is DropExitEvent) {
      target = null;
    } else {
      final result = BoxHitTestResult();
      WidgetsBinding.instance.renderView.hitTest(result, position: event.location);

      target = result.path.firstWhereOrNull((entry) => entry.target is RawDropListener)?.target as RawDropListener?;
    }

    if (_currentTargetListener != target) {
      final previous = _currentTargetListener;
      if (previous != null) {
        previous.handleDropEvent(
          DropExitEvent(
            location: previous.globalToLocalOffset(event.location),
          ),
        );
      }
      _channel.invokeMethod('updateDroppableStatus', target != null);
    }
    if (target != null) {
      final position = target.globalToLocalOffset(event.location);
      if (_currentTargetListener == null) {
        target.handleDropEvent(DropEnterEvent(location: position));
      } else {
        target.handleDropEvent(DropUpdateEvent(location: position));
      }
    }
    _currentTargetListener = target;
  }

  void _notifyDoneEvent(DropDoneEvent event) {
    final result = BoxHitTestResult();
    WidgetsBinding.instance.renderView.hitTest(result, position: event.location);

    final target = result.path.firstWhereOrNull((entry) => entry.target is RawDropListener)?.target as RawDropListener?;
    final previous = _currentTargetListener;
    if (previous != null) {
      previous.handleDropEvent(
        DropExitEvent(
          location: previous.globalToLocalOffset(event.location),
        ),
      );
      _currentTargetListener = null;
    }
    if (target != null) {
      target.handleDropEvent(
        DropDoneEvent(
          location: target.globalToLocalOffset(event.location),
          files: event.files,
        ),
      );
    }
    _channel.invokeMethod('updateDroppableStatus', false);
  }
}
