import 'dart:async';

import 'package:flutter/material.dart';
import 'package:win_toast/win_toast.dart';

void main() {
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
        aumId: 'one.mixin.example_application',
        displayName: 'Example Application',
        iconPath: '',
      );
      assert(ret);
      setState(() {
        _initialized = true;
      });
    });
    WinToast.instance().setActivatedCallback((event) {
      debugPrint('onNotificationActivated: $event');
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
        debugPrint('onNotificationDismissed: $event');
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
      crossAxisAlignment: CrossAxisAlignment.end,
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
         <image placement="appLogoOverride" hint-crop="circle" src="https://unsplash.it/64?image=1005" />
         <image src="https://picsum.photos/364/202?image=883" />
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
            await WinToast.instance().showCustomToast(xml: xml);
          },
          child: const Text('one line'),
        ),
      ],
    );
  }
}
