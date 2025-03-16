import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'windows/window_styles_selector.dart';

class WindowEventsWidget extends StatefulWidget {
  const WindowEventsWidget({super.key, required this.controller});

  final WindowController controller;

  @override
  State<WindowEventsWidget> createState() => _WindowEventsWidgetState();
}

class _WindowEventsWidgetState extends State<WindowEventsWidget>
    with WindowEvents {
  TextEditingController xPositionController = TextEditingController()
    ..text = '100';
  TextEditingController yPositionController = TextEditingController()
    ..text = '100';
  TextEditingController widthController = TextEditingController()..text = '800';
  TextEditingController heightController = TextEditingController()
    ..text = '600';

  int _windowStyle = 0x00CF0000; // Default WS_OVERLAPPEDWINDOW
  int _extendedStyle = 0x00000100; // Default WS_EX_WINDOWEDGE

  Offset _position = const Offset(0, 0);
  Size _size = const Size(0, 0);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(this);
    widget.controller.getPosition().then((position) {
      setState(() {
        _position = position;
      });
    });
    widget.controller.getSize().then((size) {
      setState(() {
        _size = size;
      });
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.titleMedium,
                        children: [
                          const TextSpan(text: 'Window Position '),
                          TextSpan(
                            text: '${_position.dx},${_position.dy}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const TextSpan(text: ' & Size '),
                          TextSpan(
                            text: '${_size.width}x${_size.height}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: xPositionController,
                            decoration: InputDecoration(
                              labelText: 'Left',
                              labelStyle: Theme.of(context).textTheme.bodySmall,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: yPositionController,
                            decoration: InputDecoration(
                              labelText: 'Top',
                              labelStyle: Theme.of(context).textTheme.bodySmall,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: widthController,
                            decoration: InputDecoration(
                              labelText: 'Width',
                              labelStyle: Theme.of(context).textTheme.bodySmall,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: heightController,
                            decoration: InputDecoration(
                              labelText: 'Height',
                              labelStyle: Theme.of(context).textTheme.bodySmall,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            final position = Offset(
                                double.parse(xPositionController.text),
                                double.parse(yPositionController.text));
                            final size = Size(
                                double.parse(widthController.text),
                                double.parse(heightController.text));
                            await widget.controller.setFrame(position & size);
                            setState(() {
                              _position = position;
                              _size = size;
                            });
                          },
                          child: const Text('Set frame'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          onPressed: () async {
                            await widget.controller.center();
                            widget.controller.getPosition().then((position) {
                              setState(() {
                                _position = position;
                              });
                            });
                            widget.controller.getSize().then((size) {
                              setState(() {
                                _size = size;
                              });
                            });
                          },
                          child: const Text('Center'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        await widget.controller.hide();
                      },
                      child: const Text('Hide'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await widget.controller.maximize();
                          },
                          child: const Text('Maximize'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            await widget.controller.unmaximize();
                          },
                          child: const Text('Unmaximize'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await widget.controller.minimize();
                          },
                          child: const Text('Minimize'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final isFullscreen =
                                await widget.controller.isFullScreen();
                            await widget.controller
                                .setFullScreen(!isFullscreen);
                          },
                          child: const Text('Toggle Fullscreen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                SizedBox(
                  height: 250,
                  width: 300,
                  child: WindowStyleSelector(
                    initialStyle: _windowStyle,
                    initialExtendedStyle: _extendedStyle,
                    onStyleChanged: (style, extendedStyle) async {
                      setState(() {
                        _windowStyle = style;
                        _extendedStyle = extendedStyle;
                      });
                    },
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    print(
                        'Setting style to $_windowStyle and extended style to $_extendedStyle');
                    await widget.controller.setStyle(
                      styleMask: MacOsWindowStyleMask.titled,
                      level: MacOsWindowLevel.normal,
                      collectionBehavior:
                          MacOsWindowCollectionBehavior.default_,
                      isOpaque: false,
                      hasShadow: false,
                      backgroundColor: Colors.red,
                      style: _windowStyle,
                      extendedStyle: _extendedStyle,
                    );
                  },
                  child: const Text('Set Style'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void onWindowMove() {
    widget.controller.getPosition().then((position) {
      setState(() {
        _position = position;
      });
    });
  }

  @override
  void onWindowMoved() {
    widget.controller.getPosition().then((position) {
      setState(() {
        _position = position;
      });
    });
  }

  @override
  void onWindowResize() {
    widget.controller.getSize().then((size) {
      setState(() {
        _size = size;
      });
    });
  }

  @override
  void onWindowResized() {
    widget.controller.getSize().then((size) {
      setState(() {
        _size = size;
      });
    });
  }
}
