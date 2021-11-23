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
  bool initialzied = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      final ret = await WinToast.instance().initialize(
          appName: 'win_toast_example',
          productName: 'win_toast_example',
          companyName: 'mixin');
      assert(ret);
      setState(() {
        initialzied = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: !initialzied
            ? const Center(child: Text('inilizing...'))
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
  var _toastCount = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () async {
            final toast = await WinToast.instance().showToast(
                type: ToastType.text01, title: "Hello ${_toastCount++}");
            assert(toast != null);
          },
          child: const Text('one line'),
        ),
        TextButton(
          onPressed: () async {
            final toast = await WinToast.instance().showToast(
              type: ToastType.text02,
              title: "Hello ${_toastCount++}",
              subtitle: '中文',
            );
            assert(toast != null);
          },
          child: const Text('two line'),
        ),
        TextButton(
          onPressed: () async {
            final toast = await WinToast.instance().showToast(
              type: ToastType.imageAndText01,
              title: "Hello",
              imagePath: '',
            );
            assert(toast != null);
          },
          child: const Text('image'),
        ),
        TextButton(
            onPressed: () async {
              final toast = await WinToast.instance().showToast(
                type: ToastType.imageAndText01,
                title: "Hello",
                actions: ["Close"],
              );
              assert(toast != null);
              toast?.eventStream.listen((event) {
                debugPrint('stream: $event');
                if (event is ActivatedEvent) {
                  WinToast.instance().bringWindowToFront();
                }
              });
            },
            child: const Text('action')),
      ],
    );
  }
}
