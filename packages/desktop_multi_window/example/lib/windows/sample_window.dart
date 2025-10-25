import 'package:flutter/material.dart';

class SampleWindow extends StatelessWidget {
  const SampleWindow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Sample Child Window'),
        ),
        body: const Column(
          children: [
            Center(
              child: Text('This is a sample child window.'),
            ),
            SizedBox(width: 15, height: 15, child: CircularProgressIndicator()),
            TextField(
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Sample Input',
              ),
            )
          ],
        ),
      ),
    );
  }
}
