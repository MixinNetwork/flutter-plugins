import 'dart:async';

import 'package:desktop_keep_screen_on/desktop_keep_screen_on.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var _duration = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
  }

  void _keepScreenOn() {
    DesktopKeepScreenOn.setPreventSleep(true);
    _timer?.cancel();
    setState(() {
      _duration = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration = _duration + const Duration(seconds: 1);
      });
    });
  }

  void _disableScreenOn() {
    _timer?.cancel();
    setState(() {
      _duration = Duration.zero;
    });
    DesktopKeepScreenOn.setPreventSleep(false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            const Spacer(),
            Center(
              child: Text('Current Time: $_duration\n'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _keepScreenOn,
              child: const Text('Keep Screen On'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _disableScreenOn,
              child: const Text('Disable Screen On'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
