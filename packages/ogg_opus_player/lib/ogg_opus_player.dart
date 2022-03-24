import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'ogg_opus_player_bindings_generated.dart';

enum PlayerState {
  idle,
  playing,
  paused,
  ended,
}

class OggOpusPlayer {
  final String _path;

  Pointer<Void> _playerHandle = nullptr;

  var _state = ValueNotifier(PlayerState.idle);

  ValueListenable<PlayerState> get state => _state;

  OggOpusPlayer(this._path) {
    debugPrint('OggOpusPlayer._init');
    _playerHandle =
        _bindings.ogg_opus_player_create(_path.toNativeUtf8().cast());
  }

  void play() {
    if (_playerHandle != nullptr) {
      _state.value = PlayerState.playing;
      _bindings.ogg_opus_player_play(_playerHandle);
    }
  }

  void pause() {
    if (_playerHandle != nullptr) {
      _state.value = PlayerState.paused;
      _bindings.ogg_opus_player_pause(_playerHandle);
    }
  }

  void dispose() {
    if (_playerHandle != nullptr) {
      _bindings.ogg_opus_player_dispose(_playerHandle);
      _playerHandle = nullptr;
    }
    _state.value = PlayerState.idle;
  }
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
final OggOpusPlayerBindings _bindings = OggOpusPlayerBindings(_dylib);
