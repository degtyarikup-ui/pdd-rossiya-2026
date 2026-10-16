import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdd_app/data/services/question_report_service.dart';
import 'package:pdd_app/data/services/godot_game_data_service.dart';
import 'package:web/web.dart' as web;

/// The Godot build of the game, in a frame on the same site: the folder
/// godot/ next to the app (scripts/godot_dev.sh web). The game leaves through
/// a postMessage with the run's summary; the frame is then closed by the owner.
class GodotWebFrame {
  static int _sequence = 0;
  static const _folder = 'godot/';

  final _frame = web.HTMLIFrameElement();
  final _container = web.HTMLDivElement();
  final _cover = web.HTMLDivElement();
  final _mascot = web.HTMLImageElement();
  final _label = web.HTMLDivElement();
  late final bool _reducedMotion;
  late final String _loadingLabel;
  late final String _returningLabel;
  static const _animation =
      'assets/assets/mascot/raster/cone-juggling-384-30.webp';
  static const _poster =
      'assets/assets/mascot/raster/cone-juggling-poster-384.webp';
  final void Function(String summaryJson) _onExit;
  final void Function(String summaryJson)? _onSummary;
  final void Function(Map<String, dynamic> event)? _onEvent;
  late final String _viewType;
  late final JSFunction _listener;
  late final JSFunction _loadListener;
  late final JSFunction _visibilityListener;
  web.MutationObserver? _failureObserver;
  bool _loading = true;
  bool _disposed = false;

  GodotWebFrame({
    required List<String> args,
    required void Function(String summaryJson) onExit,
    void Function(String summaryJson)? onSummary,
    void Function(Map<String, dynamic> event)? onEvent,
  }) : _onExit = onExit,
       _onSummary = onSummary,
       _onEvent = onEvent {
    _viewType = 'pdd-godot-${++_sequence}';
    _frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
    _frame.setAttribute('allow', 'autoplay; fullscreen');
    final query = _query(args);
    _reducedMotion =
        query.containsKey('reduce-motion') ||
        web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    _loadingLabel = query['loading-label'] ?? '';
    _returningLabel = query['returning-label'] ?? _loadingLabel;
    final dark = query.containsKey('dark');
    _container.style
      ..position = 'relative'
      ..width = '100%'
      ..height = '100%';
    _cover.style
      ..position = 'absolute'
      ..setProperty('inset', '0')
      ..zIndex = '1'
      ..display = 'flex'
      ..flexDirection = 'column'
      ..alignItems = 'center'
      ..justifyContent = 'center'
      ..backgroundColor = dark ? '#121214' : '#F8F8FA'
      ..color = dark ? '#8A90A2' : '#A1A6B7'
      ..fontFamily = 'Onest, sans-serif'
      ..fontSize = '14px';
    _cover.setAttribute('role', 'status');
    _cover.setAttribute('aria-live', 'polite');
    _mascot
      ..width = 160
      ..height = 160
      ..alt = '';
    _label.style.marginTop = '8px';
    _cover.appendChild(_mascot);
    _cover.appendChild(_label);
    _container.appendChild(_frame);
    _container.appendChild(_cover);
    _setLoading(true);
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
        if (data is! Map || data['bridge'] != 'pdd-godot') return;
        final json = data['json'];
        if (json is! String) return;
        if (data['kind'] == 'exit') {
          _onExit(json);
        } else if (data['kind'] == 'send') {
          final event = jsonDecode(json);
          if (event is Map<String, dynamic> &&
              event['event'] == 'question_report') {
            _reportQuestion(event);
          }
          if (event is Map && event['event'] == 'loading') {
            _setLoading(
              event['visible'] == true,
              returning: event['phase'] == 'returning',
            );
          }
          if (event is Map<String, dynamic>) _onEvent?.call(event);
          if (event is Map &&
              event['event'] == 'run_finished' &&
              event['summary'] is Map) {
            _onSummary?.call(jsonEncode(event['summary']));
          }
        }
      } catch (_) {
        /* Not from the game or malformed: nothing to do. */
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    _loadListener = ((web.Event _) => _watchBootstrapFailure()).toJS;
    _frame.addEventListener('load', _loadListener);
    _visibilityListener = ((web.Event _) => _updatePlayback()).toJS;
    web.document.addEventListener('visibilitychange', _visibilityListener);
    ui.platformViewRegistry.registerViewFactory(_viewType, (_) => _container);
    _frame.src = Uri.base
        .resolve('${_folder}index.html')
        .replace(queryParameters: _query(args))
        .toString();
  }

  Future<void> _reportQuestion(Map<String, dynamic> event) async {
    final id = event['request_id'];
    final payload = event['payload'];
    if (id is! String || payload is! Map<String, dynamic>) return;
    final board = payload['request_kind'] == 'leaderboard'
        ? jsonDecode(await GodotGameDataService.leaderboard())
        : null;
    final success =
        board != null || await QuestionReportService.sendGameReport(payload);
    if (_disposed) return;
    _frame.contentWindow?.postMessage(
      jsonEncode({
        'bridge': 'pdd-godot',
        'kind': 'question_report_result',
        'request_id': id,
        'success': success,
        'data': ?board,
      }).toJS,
      web.window.location.origin.toJS,
    );
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

  void _setLoading(bool visible, {bool returning = false}) {
    if (_disposed) return;
    _loading = visible;
    _cover.style.display = visible ? 'flex' : 'none';
    _label.textContent = returning ? _returningLabel : _loadingLabel;
    // A DOM image continues without a Flutter frame loop during WASM startup.
    // The hidden loader drops its animation, so no decoder runs during play.
    _updatePlayback();
  }

  void _updatePlayback() {
    final play = _loading && !_reducedMotion && !web.document.hidden;
    _mascot.src = Uri.base.resolve(play ? _animation : _poster).toString();
  }

  void _watchBootstrapFailure() {
    _failureObserver?.disconnect();
    if (_disposed) return;
    final document = _frame.contentDocument;
    if (document == null) return;
    void revealFailure() {
      final notice = document.getElementById('status-notice');
      // Godot's official export shell writes startup failures here. Reveal its
      // existing error UI instead of masking a failed engine with an endless loop.
      if ((notice?.textContent ?? '').trim().isNotEmpty ||
          document.querySelector('canvas') == null) {
        _setLoading(false);
        _failureObserver?.disconnect();
      }
    }

    _failureObserver = web.MutationObserver(
      ((JSArray<web.MutationRecord> _, web.MutationObserver _) =>
              revealFailure())
          .toJS,
    );
    _failureObserver!.observe(
      document,
      web.MutationObserverInit(
        childList: true,
        subtree: true,
        characterData: true,
      ),
    );
    revealFailure();
  }

  Widget get widget => HtmlElementView(viewType: _viewType);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    web.window.removeEventListener('message', _listener);
    _frame.removeEventListener('load', _loadListener);
    web.document.removeEventListener('visibilitychange', _visibilityListener);
    _failureObserver?.disconnect();
    _frame.src = 'about:blank';
    _mascot.src = '';
    _container.remove();
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
