import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tempDir = await getTemporaryDirectory();
  final workDir = p.join(tempDir.path, 'ogg_opus_player');
  debugPrint('workDir: $workDir');
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            _PlayAssetExample(directory: workDir),
            const SizedBox(height: 20),
            _RecorderExample(dir: workDir),
          ],
        ),
      ),
    ),
  );
}

class _PlayAssetExample extends StatefulWidget {
  const _PlayAssetExample({Key? key, required this.directory})
      : super(key: key);
  final String directory;

  @override
  _PlayAssetExampleState createState() => _PlayAssetExampleState();
}

class _PlayAssetExampleState extends State<_PlayAssetExample> {
  bool _copyCompleted = false;

  String _path = '';

  @override
  void initState() {
    super.initState();
    _copyAssets();
  }

  Future<void> _copyAssets() async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = File(p.join(dir.path, "test.ogg"));
    _path = dest.path;
    if (await dest.exists()) {
      setState(() {
        _copyCompleted = true;
      });
      return;
    }

    final bytes = await rootBundle.load('audios/test.ogg');
    await dest.writeAsBytes(bytes.buffer.asUint8List());
    setState(() {
      _copyCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _copyCompleted
        ? _OpusOggPlayerWidget(
            path: _path,
            key: ValueKey(_path),
          )
        : const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            ),
          );
  }
}

class _OpusOggPlayerWidget extends StatefulWidget {
  const _OpusOggPlayerWidget({Key? key, required this.path}) : super(key: key);

  final String path;

  @override
  State<_OpusOggPlayerWidget> createState() => _OpusOggPlayerWidgetState();
}

class _OpusOggPlayerWidgetState extends State<_OpusOggPlayerWidget> {
  OggOpusPlayer? _player;

  Timer? timer;

  double _playingPosition = 0;

  static const _kPlaybackSpeedSteps = [0.5, 1.0, 1.5, 2.0];

  int _speedIndex = 1;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _playingPosition = _player?.currentPosition ?? 0;
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _player?.state.value ?? PlayerState.idle;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('position: ${_playingPosition.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          if (state == PlayerState.playing)
            IconButton(
              onPressed: () {
                _player?.pause();
              },
              icon: const Icon(Icons.pause),
            )
          else
            IconButton(
              onPressed: () {
                _player?.dispose();
                _speedIndex = 1;
                _player = OggOpusPlayer(widget.path);
                _player?.play();
                _player?.state.addListener(() {
                  setState(() {});
                  if (_player?.state.value == PlayerState.ended) {
                    _player?.dispose();
                    _player = null;
                  }
                });
              },
              icon: const Icon(Icons.play_arrow),
            ),
          IconButton(
            onPressed: () {
              setState(() {
                _player?.dispose();
                _player = null;
              });
            },
            icon: const Icon(Icons.stop),
          ),
          if (_player != null)
            TextButton(
              onPressed: () {
                _speedIndex++;
                if (_speedIndex >= _kPlaybackSpeedSteps.length) {
                  _speedIndex = 0;
                }
                _player?.setPlaybackRate(_kPlaybackSpeedSteps[_speedIndex]);
              },
              child: Text('X${_kPlaybackSpeedSteps[_speedIndex]}'),
            ),
        ],
      ),
    );
  }
}

class _RecorderExample extends StatefulWidget {
  const _RecorderExample({
    Key? key,
    required this.dir,
  }) : super(key: key);

  final String dir;

  @override
  State<_RecorderExample> createState() => _RecorderExampleState();
}

class _RecorderExampleState extends State<_RecorderExample> {
  late String _recordedPath;

  OggOpusRecorder? _recorder;

  @override
  void initState() {
    super.initState();
    _recordedPath = p.join(widget.dir, 'test_recorded.ogg');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        if (_recorder == null)
          IconButton(
            onPressed: () {
              final file = File(_recordedPath);
              if (file.existsSync()) {
                File(_recordedPath).deleteSync();
              }
              File(_recordedPath).createSync(recursive: true);
              final recorder = OggOpusRecorder(_recordedPath);
              recorder.start();
              setState(() {
                _recorder = recorder;
              });
            },
            icon: const Icon(Icons.keyboard_voice_outlined),
          )
        else
          IconButton(
            onPressed: () async {
              await _recorder?.stop();
              debugPrint('recording stopped');
              debugPrint('duration: ${await _recorder?.duration()}');
              debugPrint('waveform: ${await _recorder?.getWaveformData()}');
              _recorder?.dispose();
              setState(() {
                _recorder = null;
              });
            },
            icon: const Icon(Icons.stop),
          ),
        const SizedBox(height: 8),
        if (_recorder == null && File(_recordedPath).existsSync())
          _OpusOggPlayerWidget(path: _recordedPath),
      ],
    );
  }
}
