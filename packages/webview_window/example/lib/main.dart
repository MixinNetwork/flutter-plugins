import 'package:flutter/material.dart';
import 'package:webview_window/webview_window.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WebviewWindow.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final TextEditingController _controller = TextEditingController(
    text: 'https://example.com',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
          actions: [
            IconButton(
              onPressed: () async {
                final webview = await WebviewWindow.create(
                  configuration: const CreateConfiguration(
                    windowHeight: 1280,
                    windowWidth: 720,
                  ),
                );
                webview.registerJavaScriptMessageHandler("test", (name, body) {
                  debugPrint('on javaScipt message: $name $body');
                });
                webview.setPromptHandler((prompt, defaultText) {
                  if (prompt == "test") {
                    return "Hello World!";
                  } else if (prompt == "init") {
                    return "initial prompt";
                  }
                  return "";
                });
                webview.launch("http://localhost:3000/test.html");
              },
              icon: const Icon(Icons.bug_report),
            )
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TextField(controller: _controller),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    final webview = await WebviewWindow.create();
                    webview.launch(_controller.text);
                  },
                  child: const Text('Open'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
