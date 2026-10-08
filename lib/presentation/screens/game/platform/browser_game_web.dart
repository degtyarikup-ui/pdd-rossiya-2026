import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// One isolated copy of the mobile engine, with a source-checked bridge.
class BrowserGame {
  static int _sequence = 0;
  final _frame = web.HTMLIFrameElement();
  final _pending = <int, Completer<Object>>{};
  late final JSFunction _listener;
  late final JSFunction _blur;
  late final String _viewType;
  int _request = 0;
  bool _disposed = false;
  bool get desktop => !web.window.matchMedia('(pointer: coarse)').matches;
  BrowserGame({
    required void Function(String) onMessage,
    required VoidCallback onBlur,
    required void Function(String, bool, bool) onKey,
    String htmlPath = 'assets/assets/game/index.html?flutterWeb=1',
    bool allowPointerEvents = false,
  }) {
    _viewType = 'pdd-game-${++_sequence}';
    _frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%'
      // The frame only draws: every control (pedals, arrows, lobby, answers)
      // is a Flutter overlay. A frame that takes pointer events swallows the
      // clicks meant for the buttons drawn over it.
      ..pointerEvents = allowPointerEvents ? 'auto' : 'none';
    _frame.setAttribute('tabindex', '-1');
    _frame.setAttribute('title', 'PDD simulator');
    // Input belongs to Flutter overlays; canvas keeps camera gestures only.
    _listener = ((web.MessageEvent event) {
      if (_disposed ||
          event.origin != web.window.location.origin ||
          event.source != _frame.contentWindow) {
        return;
      }
      final raw = event.data.dartify();
      if (raw is! String) return;
      try {
        final data = jsonDecode(raw);
        if (data['bridge'] != 'pdd-game') return;
        if (data['type'] == 'key') {
          onKey(
            data['key'] as String,
            data['down'] == true,
            data['repeat'] == true,
          );
        }
        if (data['type'] == 'blur') onBlur();
        if (data['type'] == 'event') onMessage(data['payload'] as String);
        if (data['type'] == 'result') {
          final pending = _pending.remove(data['id']);
          if (data['error'] != null) {
            pending?.completeError(StateError('Browser game command failed'));
          } else {
            pending?.complete(data['value'] ?? '');
          }
        }
      } catch (_) {
        /* Ignore unrelated or malformed frame messages. */
      }
    }).toJS;
    _blur = ((web.Event _) => onBlur()).toJS;
    web.window.addEventListener('message', _listener);
    web.window.addEventListener('blur', _blur);
    ui.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    _frame.src = Uri.base.resolve(htmlPath).toString();
  }
  Widget get widget => HtmlElementView(viewType: _viewType);
  Future<Object> runJavaScriptReturningResult(String code) async {
    if (_disposed) return '';
    final id = ++_request;
    final completer = Completer<Object>();
    _pending[id] = completer;
    _frame.contentWindow?.postMessage(
      jsonEncode({'bridge': 'pdd-game', 'id': id, 'code': code}).toJS,
      web.window.location.origin.toJS,
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> runJavaScript(String code) async {
    await runJavaScriptReturningResult(code);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    web.window.removeEventListener('message', _listener);
    web.window.removeEventListener('blur', _blur);
    for (final pending in _pending.values) {
      pending.complete('');
    }
    _pending.clear();
    _frame.src = 'about:blank';
    _frame.remove();
  }
}
