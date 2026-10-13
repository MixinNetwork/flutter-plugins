import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

class DemoTitleBar extends StatelessWidget {
  const DemoTitleBar({super.key, required this.darkMode});
  final ValueNotifier<bool> darkMode;

  @override
  Widget build(BuildContext context) {
    final state = TitleBarWebViewState.of(context);
    final controller = TitleBarWebViewController.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: darkMode,
      builder: (context, dark, _) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        child: Builder(builder: (context) {
          return Material(
            color: Theme.of(context).colorScheme.surface,
            child: Row(children: [
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
                onPressed:
                    state.isLoading ? controller.stop : controller.reload,
                icon: Icon(state.isLoading ? Icons.close : Icons.refresh,
                    size: 18),
              ),
              Expanded(
                  child: Text(state.url ?? 'Loading…',
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Close window',
                onPressed: controller.close,
                icon: const Icon(Icons.close, size: 18),
              ),
            ]),
          );
        }),
      ),
    );
  }
}
