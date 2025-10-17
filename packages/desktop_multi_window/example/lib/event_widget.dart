import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EventWidget extends StatefulWidget {
  const EventWidget({Key? key, required this.controller}) : super(key: key);

  final WindowController controller;

  @override
  State<EventWidget> createState() => _EventWidgetState();
}

class MessageItem {
  const MessageItem({this.content, required this.from, required this.method});

  final int from;
  final dynamic content;
  final String method;

  @override
  String toString() {
    return '$method($from): $content';
  }

  @override
  int get hashCode => Object.hash(from, content, method);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    final MessageItem typedOther = other as MessageItem;
    return typedOther.from == from && typedOther.content == content;
  }
}

class _EventWidgetState extends State<EventWidget> {
  final messages = <MessageItem>[];
  int? _selectedWindowId;
  List<int> _windowIds = [0];

  final textInputController = TextEditingController();

  final windowInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _updateWindowIds();
    DesktopMultiWindow.setMethodHandler(_handleMethodCallback);
  }

  @override
  dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    super.dispose();
  }

  Future<void> _updateWindowIds() async {
    // Get all sub-window IDs
    final List<int> subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
    setState(() {
      // Combine main window (0) with sub-window IDs
      _windowIds = [0, ...subWindowIds];
      // Set default selection if none selected
      _selectedWindowId ??= _windowIds.first;
    });
  }

  Future<dynamic> _handleMethodCallback(MethodCall call, int fromWindowId) async {
    if (call.arguments.toString() == "ping") {
      return "pong";
    }
    setState(() {
      messages.insert(
        0,
        MessageItem(
          from: fromWindowId,
          method: call.method,
          content: call.arguments,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    void submit() async {
      final text = textInputController.text;
      if (text.isEmpty) {
        return;
      }
      if (_selectedWindowId != null) {
        textInputController.clear();
        final result = await DesktopMultiWindow.invokeMethod(_selectedWindowId!, "onSend", text);
        debugPrint("onSend result: $result");
      } else {
        debugPrint("No window selected");
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            reverse: true,
            itemBuilder: (context, index) => _MessageItemWidget(item: messages[index]),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text('To: '),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: DropdownButton<int>(
                  value: _selectedWindowId,
                  items: _windowIds.map((int id) {
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(id == 0 ? 'Main Window' : 'Window $id'),
                    );
                  }).toList(),
                  onTap: () {
                    // Update window list before showing dropdown
                    _updateWindowIds();
                  },
                  onChanged: (int? newValue) {
                    setState(() {
                      _selectedWindowId = newValue;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: textInputController,
                  decoration: InputDecoration(
                    hintText: 'Enter message',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (text) => submit(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: submit,
                tooltip: 'Send message',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageItemWidget extends StatelessWidget {
  const _MessageItemWidget({Key? key, required this.item}) : super(key: key);

  final MessageItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text("${item.method}(${item.from})"),
      subtitle: Text(item.content.toString()),
    );
  }
}
