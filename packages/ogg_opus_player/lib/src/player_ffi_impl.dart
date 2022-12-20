import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:ogg_opus_player/src/player.dart';

import 'ogg_opus_bindings_generated.dart';
import 'player_state.dart';

class OggOpusPlayerFfiImpl extends OggOpusPlayer {
  final String _path;

  Pointer<Void> _playerHandle = nullptr;

  final ReceivePort _port;

  StreamSubscription? _portSubscription;

  final _state = ValueNotifier(PlayerState.idle);

  @override
  ValueListenable<PlayerState> get state => _state;

  @override
  double get currentPosition {
    if (_playerHandle == nullptr) {
      return 0;
    }
    return _bindings.ogg_opus_player_get_current_time(_playerHandle);
  }

  OggOpusPlayerFfiImpl(this._path)
      : _port = ReceivePort('OggOpusPlayer: #$_path'),
        super.create() {
    _initializeDartApi();
    _playerHandle = _bindings.ogg_opus_player_create(
        _path.toNativeUtf8().cast(), _port.sendPort.nativePort);
    _portSubscription = _port.listen((message) {
      if (message is int) {
        // 0: play finished
        if (message == 0) {
          _bindings.ogg_opus_player_pause(_playerHandle);
          _state.value = PlayerState.ended;
        }
      }
    });
  }

  @override
  void play() {
    if (_playerHandle != nullptr) {
      _state.value = PlayerState.playing;
      _bindings.ogg_opus_player_play(_playerHandle);
    }
  }

  @override
  void pause() {
    if (_playerHandle != nullptr) {
      _state.value = PlayerState.paused;
      _bindings.ogg_opus_player_pause(_playerHandle);
    }
  }

  @override
  void setPlaybackRate(double speed) {
    if (_playerHandle != nullptr) {
      assert(speed > 0);
      _bindings.ogg_opus_player_set_playback_rate(_playerHandle, speed);
    }
  }

  @override
  void dispose() {
    _portSubscription?.cancel();
    if (_playerHandle != nullptr) {
      _bindings.ogg_opus_player_dispose(_playerHandle);
      _playerHandle = nullptr;
    }
    _state.value = PlayerState.idle;
  }
}

bool _isolateInitialized = false;

void _initializeDartApi() {
  if (_isolateInitialized) {
    return;
  }
  _isolateInitialized = true;
  _bindings.ogg_opus_player_initialize_dart(NativeApi.initializeApiDLData);
}

const String _libName = 'ogg_opus_player';

/// The dynamic library in which the symbols for [OggOpusPlayerBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final _bindings = OggOpusBindings(_dylib);

class OggOpusRecorderFfiImpl extends OggOpusRecorder {
  final String _path;

  Pointer<Void> _recorderHandle = nullptr;
  final ReceivePort _port;

  OggOpusRecorderFfiImpl(this._path)
      : _port = ReceivePort('OggOpusRecorderFfiImpl: $_path'),
        super.create() {
    _initializeDartApi();
    _recorderHandle = _bindings.ogg_opus_recorder_create(
        _path.toNativeUtf8().cast(), _port.sendPort.nativePort);
  }

  @override
  void start() {
    if (_recorderHandle != nullptr) {
      _bindings.ogg_opus_recorder_start(_recorderHandle);
    }
  }

  @override
  Future<void> stop() {
    if (_recorderHandle != nullptr) {
      _bindings.ogg_opus_recorder_stop(_recorderHandle);
    }
    return Future.value();
  }

  @override
  void dispose() {
    if (_recorderHandle != nullptr) {
      _bindings.ogg_opus_recorder_destroy(_recorderHandle);
      _recorderHandle = nullptr;
    }
  }

  @override
  Future<double> duration() async {
    if (_recorderHandle == nullptr) {
      return 0;
    }
    return _bindings.ogg_opus_recorder_get_duration(_recorderHandle);
  }

  @override
  Future<List<int>> getWaveformData() async {
    if (_recorderHandle == nullptr) {
      return Future.value([]);
    }
    final waveDataPointer = malloc<Pointer<Uint8>>();
    final waveDataSizePointer = malloc<Int64>();
    _bindings.ogg_opus_recorder_get_wave_data(
      _recorderHandle,
      waveDataPointer,
      waveDataSizePointer,
    );
    assert(
      waveDataPointer.value != nullptr,
      'waveDataPointer.value != nullptr',
    );
    if (waveDataPointer.value == nullptr) {
      return Future.value([]);
    }
    final waveData = waveDataPointer.value
        .cast<Uint8>()
        .asTypedList(
          waveDataSizePointer.value.toInt(),
        )
        .toList();
    malloc.free(waveDataPointer);
    malloc.free(waveDataSizePointer);
    return Future.value(waveData);
  }
}
