import 'package:flutter/material.dart';
import 'package:web_qrcode/web_qrcode.dart';

void main() {
  runApp(const MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<String> decodedText = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin example app'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final str = await showQrScannerDialog(context: context);
                if (str == null) {
                  return;
                }
                setState(() {
                  decodedText.add(str);
                });
              },
              child: const Text('Start Scanner'),
            ),
            const SizedBox(height: 16),
            for (final text in decodedText)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(text),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showQrScannerDialog({
  required BuildContext context,
}) {
  return showDialog<String>(
      context: context, builder: (context) => const QrScannerDialog());
}

class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({Key? key}) : super(key: key);

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final qrCodeReaderKey = GlobalKey<QrCodeReaderState>();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: QrCodeReader(
        key: qrCodeReaderKey,
        successCallback: (decoded) async {
          await qrCodeReaderKey.currentState?.stopScanner();
          Navigator.pop(context, decoded);
        },
      ),
    );
  }
}
