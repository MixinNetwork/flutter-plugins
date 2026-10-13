import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

class DemoTitleBar extends StatelessWidget {
  const DemoTitleBar({super.key, required this.webview, required this.state});

  final Webview webview;
  final WebviewNavigationState state;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Row(children: [
        IconButton(
          tooltip: 'Back',
          onPressed: state.canGoBack ? webview.back : null,
          icon: const Icon(Icons.arrow_back, size: 18),
        ),
        IconButton(
          tooltip: 'Forward',
          onPressed: state.canGoForward ? webview.forward : null,
          icon: const Icon(Icons.arrow_forward, size: 18),
        ),
        IconButton(
          tooltip: state.isLoading ? 'Stop' : 'Reload',
          onPressed: state.isLoading ? webview.stop : webview.reload,
          icon: Icon(state.isLoading ? Icons.close : Icons.refresh, size: 18),
        ),
        Expanded(
            child: Text(state.url ?? 'Loading…',
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(
          tooltip: 'Close window',
          onPressed: webview.close,
          icon: const Icon(Icons.close, size: 18),
        ),
      ]),
    );
  }
}
