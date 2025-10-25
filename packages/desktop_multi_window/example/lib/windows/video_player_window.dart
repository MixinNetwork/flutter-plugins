import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:mixin_logger/mixin_logger.dart';
import 'package:window_manager/window_manager.dart';
import 'package:video_player/video_player.dart';

const _channel = WindowMethodChannel('example_video_player_window');

class VideoPlayerWindow extends StatelessWidget {
  const VideoPlayerWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home: Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kWindowCaptionHeight),
        child: WindowCaption(
          brightness: Theme.of(context).brightness,
          title: const Text('Video Player Window'),
        ),
      ),
      body: const VideoPlayerView(),
    ));
  }
}

// example from video_player_win package
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({Key? key}) : super(key: key);

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> with WindowListener {
  VideoPlayerController? controller;
  final httpHeaders = <String, String>{
    "User-Agent": "ergerthertherth",
    "key3": "value3_ccccc",
  };

  void reload() {
    controller?.dispose();
    // controller = VideoPlayerController.file(File("D:\\test\\test_4k.mp4"));
    //controller = WinVideoPlayerController.file(File("E:\\test_youtube.mp4"));
    //controller = VideoPlayerController.networkUrl(Uri.parse("https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8"));

    controller = VideoPlayerController.networkUrl(
      Uri.parse("https://media.w3.org/2010/05/sintel/trailer.mp4"),
      httpHeaders: httpHeaders,
    );

    //controller = WinVideoPlayerController.file(File("E:\\Downloads\\0.FDM\\sample-file-1.flac"));

    controller!.initialize().then((value) {
      if (controller!.value.isInitialized) {
        controller!.play();
        setState(() {});

        controller!.addListener(() {
          if (controller!.value.isCompleted) {
            i("ui: player completed, pos=${controller!.value.position}");
          }
        });
      } else {
        i("video file load failed");
      }
    }).catchError((e) {
      i("controller.initialize() error occurs: $e");
    });
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    reload();
    _channel.setMethodCallHandler((call) async {
      d('Received method call: ${call.method} with arguments: ${call.arguments}');
      return 'from video player window';
    });
    _channel.invokeMethod('ready');
    windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  @override
  void onWindowClose() async {
    i("Video player window onWindowClose called.");
    controller?.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void dispose() {
    super.dispose();
    controller?.dispose();
    _channel.setMethodCallHandler(null);
    windowManager.removeListener(this);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: Colors.black, child: VideoPlayer(controller!)),
        Positioned(
          bottom: 0,
          child: Column(
            children: [
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller!,
                builder: ((context, value, child) {
                  int minute = value.position.inMinutes;
                  int second = value.position.inSeconds % 60;
                  String timeStr = "$minute:$second";
                  if (value.isCompleted) timeStr = "$timeStr (completed)";
                  return Text(
                    timeStr,
                    style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                          color: Colors.white,
                          backgroundColor: Colors.black54,
                        ),
                  );
                }),
              ),
              ElevatedButton(
                onPressed: () => reload(),
                child: const Text("Reload"),
              ),
              ElevatedButton(
                onPressed: () => controller?.play(),
                child: const Text("Play"),
              ),
              ElevatedButton(
                onPressed: () => controller?.pause(),
                child: const Text("Pause"),
              ),
              ElevatedButton(
                onPressed: () => controller?.seekTo(
                  Duration(
                    milliseconds:
                        controller!.value.position.inMilliseconds + 10 * 1000,
                  ),
                ),
                child: const Text("Forward"),
              ),
              ElevatedButton(
                onPressed: () {
                  int ms = controller!.value.duration.inMilliseconds;
                  var tt = Duration(milliseconds: ms - 1000);
                  controller?.seekTo(tt);
                },
                child: const Text("End"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
