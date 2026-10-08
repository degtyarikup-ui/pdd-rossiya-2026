import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'offline events retry with original IDs and times; concurrent starts survive',
    () async {
      var online = false;
      final bodies = <Map<String, dynamic>>[];
      final reporter = UsageReporter(
        endpoint: 'https://test',
        secret: 'test',
        client: MockClient((r) async {
          expect(r.url.path, '/api/usage');
          expect(r.headers['x-install-secret'], 'test');
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', online ? 200 : 503);
        }),
      );
      await Future.wait([
        reporter.record(UsageFeature.tickets),
        reporter.record(UsageFeature.feed),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(UsageReporter.queueKey)!);
      expect(saved, hasLength(2));
      expect(saved[0]['id'], bodies.first['events'][0]['id']);
      online = true;
      await reporter.flush();
      expect(bodies.last['events'], saved);
      expect(bodies.last['installId'], bodies.first['installId']);
      expect(jsonDecode(prefs.getString(UsageReporter.queueKey)!), isEmpty);
    },
  );

  test(
    'new instance sends offline outbox in bounded batches, without losing events',
    () async {
      final events = List.generate(
        120,
        (i) => {
          'id': i.toRadixString(16).padLeft(32, '0'),
          'ts': DateTime.now().millisecondsSinceEpoch,
          'feature': 'game',
        },
      );
      SharedPreferences.setMockInitialValues({
        UsageReporter.queueKey: jsonEncode(events),
      });
      final sizes = <int>[];
      final reporter = UsageReporter(
        endpoint: 'https://test',
        secret: 'test',
        client: MockClient((r) async {
          sizes.add((jsonDecode(r.body)['events'] as List).length);
          return http.Response('{}', 200);
        }),
      );
      await reporter.flush();
      expect(sizes, [50, 50, 20]);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(UsageReporter.queueKey)!), isEmpty);
    },
  );

  test('missing application secret sends no network request', () async {
    final reporter = UsageReporter(
      endpoint: 'https://test',
      secret: '',
      client: MockClient((r) async => throw StateError('must not send')),
    );
    await reporter.record(UsageFeature.exam);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(UsageReporter.queueKey), isNull);
  });

  test(
    'unfinished training keeps its explicit mode for a resumed start',
    () async {
      final ds = ProgressDataSource();
      await ds.init();
      await ds.saveUnfinishedSession(
        title: 'Тема',
        questionIds: ['q1'],
        index: 0,
        category: TicketCategory.ab,
        usageFeature: 'topics',
      );
      expect(
        ds.loadUnfinishedSession(TicketCategory.ab)?['usageFeature'],
        'topics',
      );
    },
  );
}
