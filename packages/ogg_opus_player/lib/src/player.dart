import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:system_clock/system_clock.dart';

enum PlayerState {
  error,
  idle,
  playing,
  paused,
  ended,
}

PlayerState _convertFromRawValue(int state) {
  switch (state) {
    case 0:
      return PlayerState.ended;
    case 1:
      return PlayerState.playing;
    case 2:
      return PlayerState.paused;
    default:
      assert(false);
      return PlayerState.error;
  }
}

class OggOpusPlayer {
  static const MethodChannel _channel = MethodChannel('ogg_opus_player');

  static var _inited = false;

  static final Map<int, OggOpusPlayer> _players = {};

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    debugPrint("_handleMethodCall: ${call.method} ${call.arguments}");
    switch (call.method) {
      case "onPlayerStateChanged":
        final state = call.arguments['state'] as int;
        final position = call.arguments['position'] as double;
        final playerId = call.arguments['playerId'] as int;
        final updateTime = call.arguments['updateTime'] as int;
        final player = _players[playerId];
        if (player == null) {
          return;
        }
        player._playerState.value = _convertFromRawValue(state);
        player._lastUpdateTimeStampe = updateTime;
        player._position = position;
        break;
      default:
        break;
    }
  }

  static void _initChannelIfNeeded() {
    if (_inited) {
      return;
    }
    _inited = true;
    _channel.setMethodCallHandler((call) async {
      try {
        return await _handleMethodCall(call);
      } catch (e) {
        debugPrint("_handleMethodCall: $e");
      }
    });
  }

  OggOpusPlayer(this._path) {
    _initChannelIfNeeded();
    assert(() {
      if (_path.isEmpty) {
        throw Exception("path can not be empty");
      }
      if (!File(_path).existsSync()) {
        throw Exception("file not exists");
      }
      return true;
    }());

    scheduleMicrotask(() async {
      try {
        _playerId = await _channel.invokeMethod("create", _path);
        _players[_playerId] = this;
        _playerState.value = PlayerState.paused;
      } catch (e) {
        debugPrint('create play failed. error: $e');
        _playerState.value = PlayerState.error;
      }
      _createCompleter.complete();
    });
  }

  final String _path;

  int _playerId = -1;

  final _createCompleter = Completer<void>();

  final _playerState = ValueNotifier(PlayerState.idle);

  double _position = 0.0;

  // [_position] updated timestamp, in milliseconds.
  int _lastUpdateTimeStampe = -1;

  /// Current playing position, in seconds.
  double get currentPosition {
    if (_lastUpdateTimeStampe == -1) {
      return 0;
    }
    if (state.value != PlayerState.playing) {
      return _position;
    }
    final offset = SystemClock.uptime().inMilliseconds - _lastUpdateTimeStampe;
    assert(offset >= 0);
    if (offset < 0) {
      return _position;
    }

    return _position + offset / 1000.0;
  }

  ValueListenable<PlayerState> get state => _playerState;

  Future<void> play({bool waitCreate = true}) async {
    if (waitCreate) {
      await _createCompleter.future;
    }
    if (_playerId <= 0) {
      return;
    }
    await _channel.invokeMethod("play", _playerId);
  }

  void pause() {
    if (_playerId <= 0) {
      return;
    }
    _channel.invokeMethod("pause", _playerId);
  }

  void dispose() {
    _channel.invokeMethod("stop", _playerId);
  }
}
