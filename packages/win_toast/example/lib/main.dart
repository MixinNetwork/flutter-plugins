import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mixin_logger/mixin_logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win_toast/win_toast.dart';

void main() async {
  final dir = await getApplicationDocumentsDirectory();
  final logPath = p.join(dir.path, 'log');
  await initLogger(logPath);
  i('logPath: $logPath');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialized = false;

  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      final ret = await WinToast.instance().initialize(
        aumId: 'one.mixin.WinToastExample',
        displayName: 'Example Application',
        iconPath: '',
        clsid: '936C39FC-6BBC-4A57-B8F8-7C627E401B2F',
      );
      assert(ret);
      setState(() {
        _initialized = ret;
      });
    });
    WinToast.instance().setActivatedCallback((event) {
      i('onNotificationActivated: $event');
      showDialog(
          context: _navigatorKey.currentState!.context,
          builder: (context) {
            return AlertDialog(
              title: const Text('onNotificationActivated'),
              content: Text(event.toString()),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          });

      WinToast.instance().setDismissedCallback((event) {
        i('onNotificationDismissed: $event');
        showDialog(
            context: _navigatorKey.currentState!.context,
            builder: (context) {
              return AlertDialog(
                title: const Text('onNotificationDismissed'),
                content: Text(event.toString()),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('OK'),
                  ),
                ],
              );
            });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: !_initialized
            ? const Center(child: Text('initializing...'))
            : const Center(child: MainPage()),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () async {
            const xml = """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="action=viewConversation&amp;conversationId=9813">
   <visual>
      <binding template="ToastGeneric">
         <text>Andrew sent you a picture</text>
         <text>Check this out, Happy Canyon in Utah!</text>
      </binding>
   </visual>
   <actions>
      <input id="tbReply" type="text" placeHolderContent="Type a reply" />
      <action content="Reply" activationType="background" arguments="action=reply&amp;conversationId=9813" />
      <action content="Like" activationType="background" arguments="action=like&amp;conversationId=9813" />
      <action content="View" activationType="background" arguments="action=viewImage&amp;imageUrl=https://picsum.photos/364/202?image=883" />
   </actions>
</toast>
            """;
            try {
              await WinToast.instance().showCustomToast(xml: xml);
            } catch (error, stacktrace) {
              i('showCustomToast error: $error, $stacktrace');
            }
          },
          child: const Text('show custom'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await WinToast.instance().showToast(
                toast: Toast(
                  duration: ToastDuration.short,
                  launch: 'action=viewConversation&conversationId=9813',
                  children: [
                    ToastChildAudio(source: ToastAudioSource.defaultSound),
                    ToastChildVisual(
                      binding: ToastVisualBinding(
                        children: [
                          ToastVisualBindingChildText(
                            text: 'HelloWorld',
                            id: 1,
                          ),
                          ToastVisualBindingChildText(
                            text: 'by win_toast',
                            id: 2,
                          ),
                        ],
                      ),
                    ),
                    ToastChildActions(children: [
                      ToastAction(
                        content: "Close",
                        arguments: "close_argument",
                      )
                    ]),
                  ],
                ),
              );
            } catch (error, stacktrace) {
              i('showTextToast error: $error, $stacktrace');
            }
          },
          child: const Text('show with builder'),
        ),
      ],
    );
  }
}
