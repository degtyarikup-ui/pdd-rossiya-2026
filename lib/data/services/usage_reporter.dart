import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UsageFeature { tickets, topics, exam, game, feed }

/// Durable local outbox. Network failures never interrupt learning. Retries
/// keep the original IDs and timestamps so the server deduplicates delivery.
class UsageReporter {
  UsageReporter({
    this.endpoint = BackendConfig.notifierUrl,
    this.secret = BackendConfig.notifierSecret,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static final instance = UsageReporter();
  static const queueKey = 'usage_events_v1';
  final String endpoint;
  final String secret;
  final http.Client _client;
  Future<void> _tail = Future.value();

  static void track(UsageFeature feature) =>
      unawaited(instance.record(feature));

  Future<void> record(UsageFeature feature) => _serialize(feature);
  Future<void> flush() => _serialize(null);

  Future<void> _serialize(UsageFeature? feature) {
    _tail = _tail.then((_) async {
      if (!endpoint.startsWith('https://') || secret.isEmpty) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now().millisecondsSinceEpoch;
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
          events.add({
            'id': List.generate(
              16,
              (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
            ).join(),
            'ts': now,
            'feature': feature.name,
          });
        }
        // Bound offline storage to the 500 most recent starts.
        if (events.length > 500) events.removeRange(0, events.length - 500);
        await prefs.setString(queueKey, jsonEncode(events));
        if (events.isEmpty) return;
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
          if (response.statusCode != 200) return;
          events.removeRange(0, batch.length);
          await prefs.setString(queueKey, jsonEncode(events));
        }
      } catch (_) {
        // The saved outbox retries on another start or foreground launch.
      }
    });
    return _tail;
  }
}
