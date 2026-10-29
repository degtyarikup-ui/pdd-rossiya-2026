import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UsageFeature {
  tickets,
  topics,
  exam,
  marathon,
  feed,
  game,
  signSwiper('sign_swiper'),
  trafficController('traffic_controller'),
  roundabout('roundabout'),
  crossroads,
  roadSigns('road_signs'),
  parking;

  const UsageFeature([this.wireName]);
  final String? wireName;

  String get key => wireName ?? name;
}

/// Durable local outbox. Network failures never interrupt learning. Retries
/// keep the original IDs and timestamps so the server deduplicates delivery.
class UsageReporter {
  UsageReporter({
    this.endpoint = BackendConfig.notifierUrl,
    this.secret = BackendConfig.notifierSecret,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  static final _defaultInstance = UsageReporter();
  static UsageReporter? _testInstance;
  static UsageReporter get instance => _testInstance ?? _defaultInstance;

  @visibleForTesting
  static void setInstanceForTest(UsageReporter? reporter) =>
      _testInstance = reporter;
  static const queueKey = 'usage_events_v1';
  final String endpoint;
  final String secret;
  final http.Client _client;
  final DateTime Function() _now;
  DateTime? _nextAttemptAt;
  int _failures = 0;
  Future<void> _tail = Future.value();
  final Set<String> _gameEventIds = {};

  void _defer([http.Response? response]) {
    final delay = min(300, 30 * (1 << min(_failures, 4)));
    final requested = int.tryParse(response?.headers['retry-after'] ?? '') ?? 0;
    _nextAttemptAt = _now().add(
      Duration(seconds: max(delay, requested.clamp(0, 86400))),
    );
    _failures++;
  }

  static void track(UsageFeature feature) =>
      unawaited(instance.record(feature));

  Future<void> record(UsageFeature feature) => _serialize(feature);
  Future<void> flush() => _serialize(null);

  /// Native starts and exit snapshots reuse the same ID and original time.
  /// The server also deduplicates after a successful batch has left the outbox.
  Future<void> recordGameEvent(Map event) async {
    if (event['event'] != 'usage_start') return;
    final feature = switch (event['feature']) {
      'game' => UsageFeature.game,
      'traffic_controller' => UsageFeature.trafficController,
      'crossroads' => UsageFeature.crossroads,
      'parking' => UsageFeature.parking,
      _ => null,
    };
    final id = event['id'];
    final ts = event['ts'];
    if (feature == null ||
        id is! String ||
        !RegExp(r'^[a-zA-Z0-9:_-]{1,160}$').hasMatch(id) ||
        ts is! int ||
        ts < _now().subtract(const Duration(days: 89)).millisecondsSinceEpoch ||
        ts > _now().add(const Duration(minutes: 5)).millisecondsSinceEpoch) {
      return;
    }
    await _serialize(
      feature,
      eventId: sha256
          .convert(utf8.encode('game-usage:$id'))
          .toString()
          .substring(0, 32),
      timestamp: ts,
    );
  }

  Future<void> recordGameSummary(Map summary) async {
    final events = summary['usage_events'];
    if (events is! List) return;
    for (final event in events.whereType<Map>()) {
      await recordGameEvent(event);
    }
  }

  Future<void> _serialize(
    UsageFeature? feature, {
    String? eventId,
    int? timestamp,
  }) {
    _tail = _tail.then((_) async {
      if (!endpoint.startsWith('https://') || secret.isEmpty) return;
      if (eventId != null && _gameEventIds.contains(eventId)) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final now = _now().millisecondsSinceEpoch;
        final events = (jsonDecode(prefs.getString(queueKey) ?? '[]') as List)
            .cast<Map<String, dynamic>>()
            .where(
              (e) =>
                  e['ts'] is int &&
                  now - (e['ts'] as int) <
                      const Duration(days: 89).inMilliseconds,
            )
            .toList();
        if (feature != null) {
          final random = Random.secure();
          final id =
              eventId ??
              List.generate(
                16,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
              ).join();
          if (!events.any((e) => e['id'] == id)) {
            events.add({
              'id': id,
              'ts': timestamp ?? now,
              'feature': feature.key,
            });
          }
        }
        // Bound offline storage to the 500 most recent starts.
        if (events.length > 500) events.removeRange(0, events.length - 500);
        await prefs.setString(queueKey, jsonEncode(events));
        if (eventId != null) {
          _gameEventIds.add(eventId);
          if (_gameEventIds.length > 1000) {
            _gameEventIds.remove(_gameEventIds.first);
          }
        }
        if (events.isEmpty) return;
        if (_nextAttemptAt != null && _now().isBefore(_nextAttemptAt!)) return;
        final installId = await InstallReporter.installationId();
        while (events.isNotEmpty) {
          final batch = events.take(50).toList();
          final response = await _client
              .post(
                Uri.parse(endpoint).replace(path: '/api/usage', query: ''),
                headers: {
                  'content-type': 'application/json',
                  'x-install-secret': secret,
                },
                body: jsonEncode({
                  'installId': installId,
                  'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
                  'events': batch,
                }),
              )
              .timeout(const Duration(seconds: 10));
          if (response.statusCode != 200) {
            _defer(response);
            return;
          }
          _failures = 0;
          _nextAttemptAt = null;
          events.removeRange(0, batch.length);
          await prefs.setString(queueKey, jsonEncode(events));
        }
      } catch (_) {
        _defer();
        // The saved outbox retries on another start or foreground launch.
      }
    });
    return _tail;
  }
}
