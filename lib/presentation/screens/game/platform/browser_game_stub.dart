import 'package:flutter/widgets.dart';

class BrowserGame {
  BrowserGame({
    required void Function(String) onMessage,
    required VoidCallback onBlur,
    required void Function(String, bool, bool) onKey,
  });
  bool get desktop => false;
  Widget get widget => const SizedBox.shrink();
  Future<Object> runJavaScriptReturningResult(String code) async => '';
  Future<void> runJavaScript(String code) async {}
  Future<void> dispose() async {}
}
