import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_window_example/demo_page_server.dart';

void main() {
  test('local page provides navigation and native message bridges', () async {
    final pages = await DemoPageServer.start();
    final client = HttpClient();
    try {
      final response =
          await (await client.getUrl(Uri.parse(pages.url(7)))).close();
      final html = await response.transform(utf8.decoder).join();
      expect(html, contains('Browser 7'));
      expect(html, contains('/next?id=7'));
      expect(html, contains("window.desktopWebview.postMessage('demo'"));
      expect(html, contains('demo_window_7=hello'));
    } finally {
      client.close(force: true);
      await pages.close();
    }
  });
}
