import 'dart:io';

import 'package:flutter/foundation.dart';

import 'player_ffi_impl.dart';
import 'player_plugin_impl.dart';
import 'player_state.dart';

abstract class OggOpusPlayer {
  OggOpusPlayer.create();

  factory OggOpusPlayer(String path) {
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      return OggOpusPlayerPluginImpl(path);
    } else if (Platform.isLinux || Platform.isWindows) {
      return OggOpusPlayerFfiImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  void pause();

  void play();

  void dispose();

  ValueListenable<PlayerState> get state;

  /// Current playing position, in seconds.
  double get currentPosition;

  /// Set playback rate, in the range 0.5 through 2.0.
  /// 1.0 is normal speed (default).
  void setPlaybackRate(double speed);
}

abstract class OggOpusRecorder {
  OggOpusRecorder.create();

  factory OggOpusRecorder(String path) {
    if (Platform.isLinux || Platform.isWindows) {
      return OggOpusRecorderFfiImpl(path);
    } else if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      return OggOpusRecorderPluginImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  void start();

  Future<void> stop();

  void dispose();

  /// get the recorded audio waveform data.
  /// must be called after [stop] is called.
  Future<List<int>> getWaveformData();

  /// get the recorded audio duration.
  /// must be called after [stop] is called.
  Future<double> duration();
}
