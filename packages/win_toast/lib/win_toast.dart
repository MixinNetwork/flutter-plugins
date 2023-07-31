import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:win_toast/src/templates.dart';

export 'src/templates.dart';

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

  /// Initialize the WinToast.
  ///
  /// [aumId], [displayName], [iconPath] is config for normal exe application,
  /// wouldn't have any effect if the application is a UWP application.
  /// [clsid] is config for UWP application, wouldn't have effect for normal exe application.
  ///
  /// [aumId] application user model id.
  /// [displayName] toast application display name.
  /// [clsid] notification activator clsid, must be a valid guid string and the
  ///           same as the one in the manifest file. it's format is like this:
  ///           '00000000-0000-0000-0000-000000000000'
  Future<bool> initialize({
    required String aumId,
    required String displayName,
    required String iconPath,
    required String clsid,
  }) async {
    try {
      await _channel.invokeMethod("initialize", {
        'aumid': aumId,
        'display_name': displayName,
        'icon_path': iconPath,
        'clsid': clsid,
      });
      _supportToast = true;
    } catch (e) {
      debugPrint('initialize: ${e.toString()}');
      _supportToast = false;
    }
    return _supportToast;
  }

  /// Show a toast notification.
  /// [xml] is the raw XML content of win toast. schema can be found here:
  ///       https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/schema-root
  ///
  /// [tag] notification tag, you can use this to remove the notification.
  ///
  /// [group] notification group, you can use this to remove the notification.
  ///         Maybe this string needs to be max 16 characters to work on Windows
  ///         10 prior to applying Creators Update (build 15063).
  ///         see here: https://chromium.googlesource.com/chromium/src/+/1f65ad79494a05653e7478202e221ec229d9ed01/chrome/browser/notifications/notification_platform_bridge_win.cc#56
  Future<void> showCustomToast({
    required String xml,
    String? tag,
    String? group,
  }) async {
    if (!_supportToast) {
      return;
    }
    await _channel.invokeMethod<int>("showCustomToast", {
      'xml': xml,
      'tag': tag ?? '',
      'group': group ?? '',
    });
  }

  Future<void> showToast({
    required Toast toast,
    String? tag,
    String? group,
  }) {
    return showCustomToast(
      xml: toast.toXmlString(),
      tag: tag,
      group: group,
    );
  }

  /// Clear all notifications.
  Future<void> clear() {
    return _channel.invokeMethod('clear');
  }

  /// Clear a notification by tag, group.
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
