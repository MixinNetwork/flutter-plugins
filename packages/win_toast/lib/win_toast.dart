import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

export 'src/toast_type.dart';

enum DismissReason {
  userCanceled,
  applicationHidden,
  timeout,
}

class ActivatedEvent {
  ActivatedEvent({
    required this.argument,
    required this.userInput,
  });

  final String argument;
  final Map<String, String> userInput;

  @override
  String toString() {
    return 'ActivatedEvent{argument: $argument, userInput: $userInput}';
  }
}

class DismissedEvent {
  final DismissReason dismissReason;
  final String tag;
  final String group;

  DismissedEvent({
    required this.dismissReason,
    required this.tag,
    required this.group,
  });

  @override
  String toString() {
    return 'DismissedEvent{dismissReason: $dismissReason, tag: $tag, group: $group}';
  }
}

typedef ToastActivatedCallback = void Function(ActivatedEvent event);

typedef ToastDismissedCallback = void Function(DismissedEvent event);

class WinToast {
  WinToast._private();

  static const MethodChannel _channel = MethodChannel('win_toast');

  static WinToast? _winToast;

  static WinToast instance() {
    if (_winToast == null) {
      _winToast = WinToast._private();
      _channel.setMethodCallHandler((call) async {
        try {
          return await _winToast!._handleMethodCall(call);
        } catch (e, s) {
          debugPrint('error: $e $s');
        }
      });
    }
    return _winToast!;
  }

  bool _supportToast = false;

  ToastActivatedCallback? _activatedCallback;

  void setActivatedCallback(ToastActivatedCallback? callback) {
    _activatedCallback = callback;
  }

  ToastDismissedCallback? _dismissedCallback;

  void setDismissedCallback(ToastDismissedCallback? callback) {
    _dismissedCallback = callback;
  }

  void _onNotificationActivated(
    String argument,
    Map<String, String> userInput,
  ) {
    _activatedCallback?.call(ActivatedEvent(
      argument: argument,
      userInput: userInput,
    ));
  }

  void _onNotificationDismissed(String tag, String group, int reason) {
    _dismissedCallback?.call(DismissedEvent(
      tag: tag,
      group: group,
      dismissReason: DismissReason.values[reason],
    ));
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'OnNotificationActivated':
        final argument = call.arguments['argument'];
        final userInput = call.arguments['user_input'] as Map;
        _onNotificationActivated(argument, userInput.cast());
        break;
      case 'OnNotificationDismissed':
        final group = call.arguments['group'];
        final tag = call.arguments['tag'];
        final reason = call.arguments['reason'];
        _onNotificationDismissed(group, tag, reason);
        break;
    }
  }

  Future<bool> initialize({
    required String aumId,
    required String displayName,
    required String iconPath,
  }) async {
    try {
      _supportToast = await _channel.invokeMethod("initialize", {
        'aumid': aumId,
        'display_name': displayName,
        'icon_path': iconPath,
      });
    } catch (e) {
      debugPrint(e.toString());
      _supportToast = false;
    }
    if (!_supportToast) {
      debugPrint('did not support toast');
    }
    return _supportToast;
  }

  Future<int> showCustomToast({
    required String xml,
    Duration? expiration,
    bool expirationOnReboot = false,
    String? tag,
    String? group,
  }) async {
    if (!_supportToast) {
      return -1;
    }
    final ret = await _channel.invokeMethod<int>("showCustomToast", {
      'xml': xml,
      'tag': tag ?? '',
      'group': group ?? '',
      'expiration': expiration?.inMilliseconds ?? 0,
      'expiration_on_reboot': expirationOnReboot,
    });
    return ret ?? -1;
  }

  Future<void> clear() {
    return _channel.invokeMethod('clear');
  }

  Future<void> dismiss({
    required String tag,
    required String group,
  }) {
    return _channel.invokeMethod('dismiss', {
      'tag': tag,
      'group': group,
    });
  }
}
