import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:win_toast/src/toast_type.dart';

export 'src/toast_type.dart';

enum DismissReason {
  userCanceld,
  applicationHidden,
  timeout,
}

class Toast {
  Toast(this.id, this._client) {
    final stream = _client._activatedStream.stream;
    _subscription = stream.listen((event) {
      if (event._id != id) {
        return;
      }
      debugPrint('event: $event');
      if (event is _EndEvent) {
        _eventController.close();
        return;
      }
      _eventController.add(event);
      _subscription?.cancel();
    });
  }

  final int id;
  final WinToast _client;

  Stream<Event> get eventStream => _eventController.stream;

  final _eventController = StreamController<Event>.broadcast();

  StreamSubscription? _subscription;

  void dismiss() {
    _client._dismiss(id);
  }
}

class Event {
  final int _id;

  Event(this._id);
}

class ActivatedEvent extends Event {
  ActivatedEvent(this.actionIndex, int id) : super(id);

  final int? actionIndex;

  @override
  String toString() {
    return 'ActivatedEvent{actionIndex: $actionIndex}';
  }
}

class DissmissedEvent extends Event {
  DissmissedEvent(int id, this.dismissReason) : super(id);

  final DismissReason dismissReason;

  @override
  String toString() {
    return 'DissmissedEvent{dismissReason: $dismissReason}';
  }
}

class FailedEvent extends Event {
  FailedEvent(int id) : super(id);
}

class _EndEvent extends Event {
  _EndEvent(int id) : super(id);
}

class WinToast {
  WinToast._private();

  static const MethodChannel _channel = MethodChannel('win_toast');

  static WinToast? _winToast;

  static WinToast instance() {
    if (_winToast == null) {
      _winToast = WinToast._private();
      _channel.setMethodCallHandler((call) async {
        try {
          return await _winToast!._handleMethodcall(call);
        } catch (e, s) {
          debugPrint('error: $e $s');
        }
      });
    }
    return _winToast!;
  }

  bool _supportToast = false;

  final _activatedStream = StreamController<Event>.broadcast();

  Future<dynamic> _handleMethodcall(MethodCall call) async {
    if (call.method != 'OnNotificationStatusChanged') {
      return;
    }
    final String action = call.arguments['action'];
    final int id = call.arguments['id'];
    assert(id != -1);

    switch (action) {
      case 'activated':
        _activatedStream.add(
          ActivatedEvent(call.arguments['actionIndex'], id),
        );
        break;
      case 'dismissed':
        final int reason = call.arguments['reason'];
        assert(const [0, 1, 2].contains(reason));
        _activatedStream.add(DissmissedEvent(id, DismissReason.values[reason]));
        break;
      case 'failed':
        _activatedStream.add(FailedEvent(id));
        break;
      case 'end':
        _activatedStream.add(_EndEvent(id));
        break;
      default:
        break;
    }
  }

  Future<bool> initialize({
    required String appName,
    required String productName,
    required String companyName,
  }) async {
    try {
      _supportToast = await _channel.invokeMethod("initialize", {
        'app_name': appName,
        'product_name': productName,
        'company_name': companyName,
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

  /// return notification id. -1 meaning failed to show.
  Future<Toast?> showToast({
    required ToastType type,
    required String title,
    String subtitle = '',
    String imagePath = '',
    List<String> actions = const <String>[],
  }) async {
    if (!_supportToast) {
      return null;
    }
    assert(title.isNotEmpty);
    assert(type.textFiledCount() > 1 || subtitle.isEmpty);
    final id = await _channel.invokeMethod('showToast', {
      'type': type.index,
      'title': title,
      'subtitle': subtitle,
      'imagePath': imagePath,
      'actions': actions,
    });
    debugPrint('id: $id');
    if (id == -1 || id == null) {
      return null;
    }
    return Toast(id, this);
  }

  Future<void> clear() {
    return _channel.invokeMethod('clear');
  }

  Future<void> _dismiss(int id) {
    return _channel.invokeMethod('hide', id);
  }

  Future<void> bringWindowToFront() {
    return _channel.invokeMethod('bringWindowToFront');
  }
}
