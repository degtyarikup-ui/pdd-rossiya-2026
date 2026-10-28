import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const fixture = 'test-only';
  test(
    'offline events persist, retry after restart, and repeated views do not enqueue again',
    () async {
      SharedPreferences.setMockInitialValues({});
      const id = 'c069e042-5b7b-40a0-b15e-b80c4444ce1d';
      final offline = RemoteNotificationsService.forTesting(
        client: MockClient((_) async => http.Response('', 503)),
        userProvider: () => null,
        metricsSecret: fixture,
      );
      await offline.recordNoticeEvent(id, 'view');
      await offline.recordNoticeEvent(id, 'click');
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('notifications_ru_metrics_queue')!),
        hasLength(2),
      );
      final batches = <List<dynamic>>[];
      final online = RemoteNotificationsService.forTesting(
        client: MockClient((request) async {
          expect(request.url.path, '/api/notifications/events');
          expect(request.headers['x-install-secret'], 'test-only');
          final body = jsonDecode(request.body) as Map;
          expect(body['installId'], matches(RegExp(r'^[a-f0-9]{32}$')));
          batches.add(body['events'] as List);
          return http.Response('{"ok":true}', 200);
        }),
        userProvider: () => null,
        metricsSecret: fixture,
      );
      await online.flushMetrics();
      expect(batches.single.map((e) => e['event']), ['view', 'click']);
      expect(prefs.getString('notifications_ru_metrics_queue'), '[]');
      await online.recordNoticeEvent(id, 'view');
      await online.recordNoticeEvent(id, 'click');
      expect(batches, hasLength(1));
    },
  );
}
