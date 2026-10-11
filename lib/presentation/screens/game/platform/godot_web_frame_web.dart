import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// The Godot build of the game, in a frame on the same site: the folder
/// godot/ next to the app (scripts/godot_dev.sh web). The game leaves through
/// a postMessage with the run's summary; the frame is then closed by the owner.
class GodotWebFrame {
  static int _sequence = 0;
  static const _folder = 'godot/';

  final _frame = web.HTMLIFrameElement();
  final void Function(String summaryJson) _onExit;
  late final String _viewType;
  late final JSFunction _listener;
  bool _disposed = false;

  GodotWebFrame({
    required List<String> args,
    required void Function(String summaryJson) onExit,
  }) : _onExit = onExit {
    _viewType = 'pdd-godot-${++_sequence}';
    _frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
    _frame.setAttribute('allow', 'autoplay; fullscreen');
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
        if (data is! Map ||
            data['bridge'] != 'pdd-godot' ||
            data['kind'] != 'exit') {
          return;
        }
        final json = data['json'];
        if (json is String) _onExit(json);
      } catch (_) {
        /* Not from the game or malformed: nothing to do. */
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    ui.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    _frame.src = Uri.base
        .resolve('${_folder}index.html')
        .replace(queryParameters: _query(args))
        .toString();
  }

  /// Whether the game is on this site: its pack is there. A site without the
  /// build answers 404, or an HTML page for any path (single-page fallback).
  static Future<bool> available() async {
    try {
      final url = Uri.base.resolve('${_folder}index.pck').toString();
      final res = await web.window
          .fetch(url.toJS, web.RequestInit(method: 'HEAD'))
          .toDart;
      final type = res.headers.get('content-type') ?? '';
      return res.ok && !type.contains('text/html');
    } catch (_) {
      return false;
    }
  }

  Widget get widget => HtmlElementView(viewType: _viewType);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    web.window.removeEventListener('message', _listener);
    _frame.src = 'about:blank';
    _frame.remove();
  }

  /// `--lang=ru --dark` becomes `?lang=ru&dark=1` (the game reads the query).
  static Map<String, String> _query(List<String> args) {
    final query = <String, String>{};
    for (final arg in args) {
      if (!arg.startsWith('--')) continue;
      final body = arg.substring(2);
      final eq = body.indexOf('=');
      if (eq < 0) {
        query[body] = '1';
      } else {
        query[body.substring(0, eq)] = body.substring(eq + 1);
      }
    }
    return query;
  }
}
