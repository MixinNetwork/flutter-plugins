import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: _copyCompleted
            ? PlayerBody(path: _path)
            : const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(),
                ),
              ),
      ),
    );
  }
}

class PlayerBody extends StatefulWidget {
  const PlayerBody({Key? key, required this.path}) : super(key: key);

  final String path;

  @override
  State<PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<PlayerBody> {
  late OggOpusPlayer _player;

  Timer? timer;

  double _playingPosition = 0;

  @override
  void initState() {
    super.initState();
    _player = OggOpusPlayer(widget.path);
    timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        // _playingPosition = _player.currentPosition;
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('position: ${_playingPosition.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          IconButton(
            onPressed: () {
              setState(() {
                _player.dispose();
                _player = OggOpusPlayer(widget.path);
              });
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: _player.state,
            builder: (context, state, child) {
              if (state == PlayerState.playing) {
                return IconButton(
                  onPressed: () {
                    _player.pause();
                  },
                  icon: const Icon(Icons.pause),
                );
              } else {
                return IconButton(
                  onPressed: () {
                    if (state == PlayerState.ended) {
                      _player.dispose();
                      _player = OggOpusPlayer(widget.path);
                      _player.play();
                    } else {
                      _player.play();
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
