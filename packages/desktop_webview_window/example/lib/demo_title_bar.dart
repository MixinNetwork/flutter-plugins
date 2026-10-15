import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

class DemoTitleBar extends StatelessWidget {
  const DemoTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = TitleBarWebViewState.of(context);
    final controller = TitleBarWebViewController.of(context);
    return Row(children: [
      IconButton(
        tooltip: 'Back',
        onPressed: state.canGoBack ? controller.back : null,
        icon: const Icon(Icons.arrow_back, size: 18),
      ),
      IconButton(
        tooltip: 'Forward',
        onPressed: state.canGoForward ? controller.forward : null,
        icon: const Icon(Icons.arrow_forward, size: 18),
      ),
      IconButton(
        tooltip: state.isLoading ? 'Stop' : 'Reload',
        onPressed: state.isLoading ? controller.stop : controller.reload,
        icon: Icon(state.isLoading ? Icons.close : Icons.refresh, size: 18),
      ),
      Expanded(
        child: Text(state.url ?? 'Loading…',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      IconButton(
        tooltip: 'Close window',
        onPressed: controller.close,
        icon: const Icon(Icons.close, size: 18),
      ),
    ]);
  }
}
