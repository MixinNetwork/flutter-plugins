import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

late AudioSession session;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tempDir = await getTemporaryDirectory();
  final workDir = p.join(tempDir.path, 'ogg_opus_player');
  debugPrint('workDir: $workDir');
  session = await AudioSession.instance;
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
  const _PlayAssetExample({required this.directory});
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
  const _OpusOggPlayerWidget({super.key, required this.path});

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
              onPressed: () async {
                _player?.dispose();
                _speedIndex = 1;
                _player = OggOpusPlayer(widget.path);
                session.configure(const AudioSessionConfiguration.music());
                bool active = await session.setActive(true);
                debugPrint('active: $active');
                _player?.play();
                _player?.state.addListener(() async {
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
                debugPrint('ended');
                _player?.dispose();
                _player = null;
                session.setActive(false).then((value) {
                  debugPrint('active: $value');
                }).onError((error, stackTrace) {
                  debugPrint('error: $error');
                });
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
  const _RecorderExample({required this.dir});

  final String dir;

  @override
  State<_RecorderExample> createState() => _RecorderExampleState();
}

class _RecorderExampleState extends State<_RecorderExample> {
  late String _recordedPath;

  OggOpusRecorder? _recorder;
  StreamSubscription<OggOpusTranscription>? _transcriptionSubscription;
  String _transcriptionText = '';
  bool _isTranscribingFile = false;

  @override
  void initState() {
    super.initState();
    _recordedPath = p.join(widget.dir, 'test_recorded.ogg');
  }

  Future<bool> _requestMicrophonePermission() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) {
      final status = await Permission.microphone.request();
      return status.isGranted;
    }
    return true;
  }

  Future<bool> _canUseSpeechRecognition() async {
    if (!(Platform.isIOS || Platform.isMacOS)) {
      return false;
    }
    try {
      final status = await OggOpusSpeechRecognizer.authorizationStatus();
      return status == OggOpusSpeechAuthorizationStatus.authorized;
    } catch (error) {
      debugPrint('speech recognition authorization status failed: $error');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final systemLocaleIdentifier = systemLocale.toLanguageTag();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        if (_recorder == null)
          IconButton(
            onPressed: () async {
              final isGranted = await _requestMicrophonePermission();
              if (!isGranted) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('need microphone permission')),
                  );
                }
                return;
              }
              try {
                final instance = await AudioSession.instance;
                await instance.configure(
                  const AudioSessionConfiguration(
                    avAudioSessionCategory:
                        AVAudioSessionCategory.playAndRecord,
                    avAudioSessionMode: AVAudioSessionMode.spokenAudio,
                  ),
                );
                await instance.setActive(true);
              } catch (error, stacktrace) {
                debugPrint(
                    'AudioSession activeRecord error: $error $stacktrace');
              }

              final enableTranscription = await _canUseSpeechRecognition();

              final file = File(_recordedPath);
              if (file.existsSync()) {
                File(_recordedPath).deleteSync();
              }
              File(_recordedPath).createSync(recursive: true);
              await session.configure(const AudioSessionConfiguration(
                avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
                avAudioSessionCategoryOptions:
                    AVAudioSessionCategoryOptions.allowBluetooth,
                avAudioSessionMode: AVAudioSessionMode.spokenAudio,
              ));
              await session.setActive(true);
              final recorder = OggOpusRecorder(
                _recordedPath,
                enableTranscription: enableTranscription,
                transcriptionLocaleIdentifier: systemLocaleIdentifier,
              );
              _transcriptionSubscription =
                  recorder.transcriptions.listen((transcription) {
                setState(() {
                  _transcriptionText = transcription.text;
                });
              }, onError: (Object error) {
                debugPrint('transcription error: $error');
              });
              recorder.start();
              setState(() {
                _recorder = recorder;
                _transcriptionText = '';
              });
            },
            icon: const Icon(Icons.keyboard_voice_outlined),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(),
              ),
              IconButton(
                onPressed: () async {
                  await _recorder?.stop();
                  await _transcriptionSubscription?.cancel();
                  _transcriptionSubscription = null;
                  debugPrint('recording stopped');
                  debugPrint('duration: ${await _recorder?.duration()}');
                  debugPrint('waveform: ${await _recorder?.getWaveformData()}');
                  _recorder?.dispose();
                  setState(() {
                    _recorder = null;
                    session.setActive(
                      false,
                      avAudioSessionSetActiveOptions:
                          AVAudioSessionSetActiveOptions
                              .notifyOthersOnDeactivation,
                    );
                  });
                },
                icon: const Icon(Icons.stop),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (_recorder == null && File(_recordedPath).existsSync())
          _OpusOggPlayerWidget(path: _recordedPath),
        if (_recorder == null &&
            File(_recordedPath).existsSync() &&
            (Platform.isIOS || Platform.isMacOS))
          IconButton(
            onPressed: _isTranscribingFile
                ? null
                : () async {
                    setState(() {
                      _isTranscribingFile = true;
                    });
                    try {
                      await OggOpusSpeechRecognizer.requestAuthorization();
                      final transcription =
                          await OggOpusSpeechRecognizer.transcribeFile(
                        _recordedPath,
                        localeIdentifier: systemLocaleIdentifier,
                      );
                      setState(() {
                        _transcriptionText = transcription.text;
                      });
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isTranscribingFile = false;
                        });
                      }
                    }
                  },
            icon: _isTranscribingFile
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator.adaptive(),
                  )
                : const Icon(Icons.text_fields),
          ),
        if (_transcriptionText.isNotEmpty) Text(_transcriptionText),
      ],
    );
  }

  @override
  void dispose() {
    _transcriptionSubscription?.cancel();
    _recorder?.dispose();
    super.dispose();
  }
}
