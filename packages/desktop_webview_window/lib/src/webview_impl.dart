import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'webview.dart';

class WebviewImpl extends Webview {
  final int viewId;

  final MethodChannel channel;

  final Map<String, JavaScriptMessageHandler> _javaScriptMessageHandlers = {};

  bool _closed = false;

  PromptHandler? _promptHandler;

  final _closeCompleter = Completer<void>();

  WebviewImpl(this.viewId, this.channel);

  @override
  Future<void> get onClose => _closeCompleter.future;

  void onClosed() {
    _closed = true;
    _closeCompleter.complete();
  }

  void onJavaScriptMessage(String name, dynamic body) {
    assert(!_closed);
    final handler = _javaScriptMessageHandlers[name];
    assert(handler != null, "handler $name is not registed.");
    handler?.call(name, body);
  }

  String onRunJavaScriptTextInputPanelWithPrompt(
      String prompt, String defaultText) {
    assert(!_closed);
    return _promptHandler?.call(prompt, defaultText) ?? defaultText;
  }

  @override
  void registerJavaScriptMessageHandler(
      String name, JavaScriptMessageHandler handler) {
    if (!Platform.isMacOS) {
      return;
    }
    assert(!_closed);
    if (_closed) {
      return;
    }
    assert(name.isNotEmpty);
    assert(!_javaScriptMessageHandlers.containsKey(name));
    _javaScriptMessageHandlers[name] = handler;
    channel.invokeMethod("registerJavaScripInterface", {
      "viewId": viewId,
      "name": name,
    });
  }

  @override
  void unregisterJavaScriptMessageHandler(String name) {
    if (!Platform.isMacOS) {
      return;
    }
    if (_closed) {
      return;
    }
    channel.invokeMethod("unregisterJavaScripInterface", {
      "viewId": viewId,
      "name": name,
    });
  }

  @override
  void setPromptHandler(PromptHandler? handler) {
    if (!Platform.isMacOS) {
      return;
    }
    _promptHandler = handler;
  }

  @override
  void launch(String url) {
    channel.invokeMethod("launch", {
      "url": url,
      "viewId": viewId,
    });
  }

  @override
  void setBrightness(Brightness? brightness) {
    /// -1 : system default
    /// 0 : dark
    /// 1 : light
    if (!Platform.isMacOS) {
      return;
    }
    channel.invokeMethod("setBrightness", {
      "viewId": viewId,
      "brightness": brightness?.index ?? -1,
    });
  }

  @override
  void addScriptToExecuteOnDocumentCreated(String javaScript) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    assert(javaScript.trim().isNotEmpty);
    channel.invokeMethod("addScriptToExecuteOnDocumentCreated", {
      "viewId": viewId,
      "javaScript": javaScript,
    });
  }
}
