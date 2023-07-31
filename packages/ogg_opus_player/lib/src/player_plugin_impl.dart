import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:system_clock/system_clock.dart';

import 'player.dart';
import 'player_state.dart';

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

const MethodChannel _channel = MethodChannel('ogg_opus_player');

final Map<int, OggOpusPlayerPluginImpl> _players = {};
final Map<int, OggOpusRecorderPluginImpl> _recorders = {};

var _initialized = false;

void _initChannelIfNeeded() {
  if (_initialized) {
    return;
  }
  _initialized = true;
  _channel.setMethodCallHandler((call) async {
    try {
      return await _handleMethodCall(call);
    } catch (error, stacktrace) {
      debugPrint("_handleMethodCall: $error $stacktrace");
    }
  });
}

Future<dynamic> _handleMethodCall(MethodCall call) async {
  switch (call.method) {
    case "onPlayerStateChanged":
      final state = call.arguments['state'] as int;
      final position = call.arguments['position'] as double;
      final playerId = call.arguments['playerId'] as int;
      final updateTime = call.arguments['updateTime'] as int;
      final speed = call.arguments['speed'] as double?;
      final player = _players[playerId];
      if (player == null) {
        return;
      }
      player._playerState.value = _convertFromRawValue(state);
      player._lastUpdateTimeStamp = updateTime;
      player._position = position;
      player._playbackRate = speed ?? 1.0;
      break;
    case "onRecorderCanceled":
      final recorderId = call.arguments['recorderId'] as int;
      final recorder = _recorders[recorderId];
      final reason = call.arguments['reason'] as int;
      if (recorder == null) {
        return;
      }
      recorder.onCanceled(reason);
      break;
    case "onRecorderStartFailed":
      final recorderId = call.arguments['recorderId'] as int;
      final recorder = _recorders[recorderId];
      if (recorder == null) {
        return;
      }
      final reason = call.arguments['error'] as String;
      debugPrint('onRecorderStartFailed: $reason');
      break;
    case "onRecorderFinished":
      final recorderId = call.arguments['recorderId'] as int;
      final recorder = _recorders[recorderId];
      if (recorder == null) {
        return;
      }
      final duration = call.arguments['duration'] as int;
      final waveform = (call.arguments['waveform'] as List).cast<int>();
      recorder.onFinished(duration, waveform);
      break;
    default:
      break;
  }
}

class OggOpusPlayerPluginImpl extends OggOpusPlayer {
  OggOpusPlayerPluginImpl(this._path) : super.create() {
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
      } catch (error, stacktrace) {
        debugPrint('create play failed. error: $error $stacktrace');
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
  int _lastUpdateTimeStamp = -1;

  double _playbackRate = 1.0;

  @override
  double get currentPosition {
    if (_lastUpdateTimeStamp == -1) {
      return 0;
    }
    if (state.value != PlayerState.playing) {
      return _position;
    }
    final offset = SystemClock.uptime().inMilliseconds - _lastUpdateTimeStamp;
    assert(offset >= 0);
    if (offset < 0) {
      return _position;
    }

    return _position + (offset / 1000.0) * _playbackRate;
  }

  @override
  ValueListenable<PlayerState> get state => _playerState;

  @override
  Future<void> play({bool waitCreate = true}) async {
    if (waitCreate) {
      await _createCompleter.future;
    }
    if (_playerId <= 0) {
      return;
    }
    await _channel.invokeMethod("play", _playerId);
  }

  @override
  void pause() {
    if (_playerId <= 0) {
      return;
    }
    _channel.invokeMethod("pause", _playerId);
  }

  @override
  Future<void> setPlaybackRate(double speed) async {
    await _createCompleter.future;
    if (_playerId <= 0) {
      return;
    }
    await _channel.invokeMethod('setPlaybackSpeed', {
      'playerId': _playerId,
      'speed': speed,
    });
  }

  @override
  void dispose() {
    _channel.invokeMethod("stop", _playerId);
  }
}

class OggOpusRecorderPluginImpl extends OggOpusRecorder {
  OggOpusRecorderPluginImpl(this._path) : super.create() {
    _initChannelIfNeeded();
    scheduleMicrotask(() async {
      try {
        _id = await _channel.invokeMethod('createRecorder', _path);
        _recorders[_id] = this;
      } catch (e) {
        debugPrint('create recorder failed. error: $e');
      }
      _createCompleter.complete();
    });
  }

  final String _path;
  int _id = -1;

  double? _duration;
  List<int>? _waveformData;

  final _createCompleter = Completer<void>();

  final _stopCompleter = Completer<void>();

  @override
  Future<void> start() async {
    await _createCompleter.future;
    if (_id <= 0) {
      return;
    }
    await _channel.invokeMethod('startRecord', _id);
  }

  @override
  Future<void> stop() async {
    await _createCompleter.future;
    if (_id <= 0) {
      return;
    }
    await _channel.invokeMethod('stopRecord', _id);
    await _stopCompleter.future;
  }

  @override
  void dispose() {
    _channel.invokeMethod("destroyRecorder", _id);
  }

  @override
  Future<double> duration() async {
    return _duration ?? 0.0;
  }

  @override
  Future<List<int>> getWaveformData() async {
    return _waveformData ?? [];
  }

  void onCanceled(int reason) {
    _stopCompleter.complete();
  }

  void onFinished(int duration, List<int> waveform) {
    _duration = duration / 1000;
    _waveformData = waveform;
    _stopCompleter.complete();
  }
}
