import 'package:flutter/material.dart';

import 'message_channel.dart';

const _channel = ClientMessageChannel();

bool runWebViewTitleBarWidget(List<String> args) {
  if (args.isEmpty || args[0] != 'web_view_title_bar') {
    return false;
  }
  final webViewId = int.tryParse(args[1]);
  if (webViewId == null) {
    return false;
  }
  final titleBarTopPadding = int.tryParse(args.length > 2 ? args[2] : '0') ?? 0;
  debugPrint('runWebViewTitleBarWidget: $webViewId, $titleBarTopPadding');
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _TitleBar(
      webViewId: webViewId,
      titleBarTopPadding: titleBarTopPadding,
    ),
  ));
  return true;
}

class _TitleBar extends StatefulWidget {
  const _TitleBar({
    Key? key,
    required this.webViewId,
    required this.titleBarTopPadding,
  }) : super(key: key);

  final int webViewId;

  final int titleBarTopPadding;

  @override
  State<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<_TitleBar> {
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _channel.setMessageHandler((call) async {
      final args = call.arguments as Map;
      final webViewId = args['webViewId'] as int;
      if (webViewId != widget.webViewId) {
        return;
      }
      switch (call.method) {
        case "onHistoryChanged":
          setState(() {
            _canGoBack = args['canGoBack'] as bool;
            _canGoForward = args['canGoForward'] as bool;
          });
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(top: widget.titleBarTopPadding.toDouble()),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              splashRadius: 16,
              iconSize: 16,
              onPressed: !_canGoBack
                  ? null
                  : () {
                      _channel.invokeMethod('onBackPressed', {
                        'webViewId': widget.webViewId,
                      });
                    },
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              splashRadius: 16,
              iconSize: 16,
              onPressed: !_canGoForward
                  ? null
                  : () {
                      _channel.invokeMethod('onForwardPressed', {
                        'webViewId': widget.webViewId,
                      });
                    },
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              splashRadius: 16,
              iconSize: 16,
              onPressed: () {
                _channel.invokeMethod('onRefreshPressed', {
                  'webViewId': widget.webViewId,
                });
              },
              icon: const Icon(Icons.refresh),
            ),
            const Spacer()
          ],
        ),
      ),
    );
  }
}
