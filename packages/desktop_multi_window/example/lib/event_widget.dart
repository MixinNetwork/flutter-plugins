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

  final textInputController = TextEditingController();

  final windowInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    DesktopMultiWindow.setMethodHandler(_handleMethodCallback);
  }

  @override
  dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleMethodCallback(
      MethodCall call, int fromWindowId) async {
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
      final windowId = int.tryParse(windowInputController.text);
      textInputController.clear();
      final result =
          await DesktopMultiWindow.invokeMethod(windowId!, "onSend", text);
      debugPrint("onSend result: $result");
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            reverse: true,
            itemBuilder: (context, index) =>
                _MessageItemWidget(item: messages[index]),
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 100,
              child: TextField(
                controller: windowInputController,
                decoration: const InputDecoration(
                  labelText: 'Window ID',
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            Expanded(
              child: TextField(
                controller: textInputController,
                decoration: const InputDecoration(
                  hintText: 'Enter message',
                ),
                onSubmitted: (text) => submit(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: submit,
            ),
          ],
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
