import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';
// SharedPreferences' installed platform interface supplies the actual storage
// test seam; this test does not add a production package dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Auth extends AuthService {
  _Auth() : super.forTesting(writeSession: (_) async {});
  UserProfile? user = _user('google_a');
  int revision = 0;
  @override
  UserProfile? get currentUser => user;
  @override
  int get accountRevision => revision;
  @override
  bool get hasServerSession => user != null;
  @override
  Map<String, String> get serverHeaders => {
    'content-type': 'application/json',
    'authorization': 'Bearer fixture-${user?.id}',
  };
  void account(String? id) {
    user = id == null ? null : _user(id);
    revision++;
    notifyListeners();
  }
}

class _ControlledImportSource extends ProgressDataSource {
  Future<void> Function()? beforeImport;
  @override
  Future<void> importProgressSnapshot(
    Map<String, dynamic> data, {
    bool Function()? stillCurrent,
  }) async {
    await beforeImport?.call();
    await super.importProgressSnapshot(data, stillCurrent: stillCurrent);
  }
}

class _FailOneAcknowledgement extends SharedPreferencesStorePlatform {
  _FailOneAcknowledgement(this.backend);
  final SharedPreferencesStorePlatform backend;
  int failedWrites = 0;
  Map<String, dynamic>? retainedAtFailure;
  @override
  Future<bool> clear() => backend.clear();
  @override
  Future<Map<String, Object>> getAll() => backend.getAll();
  @override
  Future<bool> remove(String key) => backend.remove(key);
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failedWrites == 0 &&
        key.contains('progress_sync_outbox_v1:') &&
        value is String) {
      final record = jsonDecode(value) as Map<String, dynamic>;
      if (record['revision'] == record['acknowledgedRevision'] &&
          record['revision'] > 0) {
        final persisted = (await backend.getAll())[key] as String;
        retainedAtFailure = jsonDecode(persisted) as Map<String, dynamic>;
        failedWrites++;
        return false;
      }
    }
    return backend.setValue(valueType, key, value);
  }
}

UserProfile _user(String id) => UserProfile(
  id: id,
  name: 'Fixture',
  email: '',
  provider: AuthProviderType.google,
  createdAt: DateTime(2026),
);

Future<void> _answer(ProgressDataSource source, String id) => source.saveAnswer(
  questionId: id,
  isCorrect: true,
  selectedAnswerIndex: 1,
  category: TicketCategory.ab,
);
Map<String, dynamic> _payload(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;
http.Response _echo(http.Request request, {Map<String, dynamic>? progress}) =>
    http.Response(
      jsonEncode({
        'ok': true,
        'progress': progress ?? _payload(request)['progress'],
      }),
      200,
    );

Future<Map<String, dynamic>> _outbox([String id = 'google_a']) async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(
        prefs.getString('progress_sync_outbox_v1:${Uri.encodeComponent(id)}') ??
            '{}',
      )
      as Map<String, dynamic>;
}

Future<void> _until(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Progress condition did not converge');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<bool> _acknowledged() async {
  final record = await _outbox();
  return record['revision'] != null &&
      record['revision'] == record['acknowledgedRevision'];
}

ProgressSyncService _service(
  _Auth auth,
  ProgressDataSource source, {
  Duration base = const Duration(milliseconds: 20),
  Duration cap = const Duration(milliseconds: 80),
}) {
  final service = ProgressSyncService.forTesting(
    auth: auth,
    retryBase: base,
    retryCap: cap,
    jitter: () => 0.5,
  );
  service.init(source);
  addTearDown(service.dispose);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameGarageService.instance.resetForTest();
    NotifierRoute.reset();
    PackageInfo.setMockInitialValues(
      appName: 'Fixture',
      packageName: 'fixture.invalid',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test(
    'an edit during upload is persisted before the old reply and automatically follows it',
    () async {
      final source = ProgressDataSource();
      await source.init();
      final auth = _Auth(), held = Completer<http.Response>();
      final requests = <http.Request>[];
      await _answer(source, 'first');
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          final uploading = service.syncWithServer();
          await _until(() => requests.length == 1);
          expect((await _outbox())['acknowledgedRevision'], 0);
          await _answer(source, 'during');
          service.scheduleSync(delay: Duration.zero);
          await _until(() async => (await _outbox())['revision'] == 2);
          final dirty = await _outbox();
          expect(
            (dirty['snapshot'] as Map)['questionProgressAb'],
            contains('during'),
          );
          held.complete(_echo(requests.first));
          await uploading;
          await _until(() => requests.length == 2);
          expect(
            (_payload(requests[0])['progress'] as Map)['questionProgressAb'],
            isNot(contains('during')),
          );
          expect(
            (_payload(requests[1])['progress'] as Map)['questionProgressAb'],
            contains('during'),
          );
          await _until(_acknowledged);
          expect(
            await source.isQuestionAnswered('during', TicketCategory.ab),
            isTrue,
          );
          expect(
            (await _outbox())['snapshot'],
            isNull,
            reason: 'completed queues retain only an acknowledgement hash',
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));
          expect(
            requests.length,
            2,
            reason: 'the server import must not perpetually enqueue itself',
          );
        },
        () => MockClient((request) {
          requests.add(request);
          return requests.length == 1
              ? held.future
              : Future.value(_echo(request));
        }),
      );
    },
  );

  test(
    'a lost response retries the same idempotent snapshot after transport recovery',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'offline');
      final auth = _Auth();
      final bodies = <String>[];
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          await service.syncWithServer();
          final pending = await _outbox();
          expect(
            pending['revision'],
            greaterThan(pending['acknowledgedRevision'] as int),
          );
          expect(
            await source.isQuestionAnswered('offline', TicketCategory.ab),
            isTrue,
          );
          await _until(_acknowledged);
          expect(
            bodies.length,
            3,
            reason:
                'two transport routes fail, then one scheduled attempt recovers',
          );
          expect(
            bodies.toSet().length,
            1,
            reason:
                'a lost response is a snapshot replay, never an increment action',
          );
        },
        () => MockClient((request) async {
          bodies.add(request.body);
          if (bodies.length <= 2) {
            throw http.ClientException('fixture lost response');
          }
          return _echo(request);
        }),
      );
    },
  );

  test(
    '503 Retry-After survives restart and edits or explicit sync cannot bypass its cooldown',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'first');
      final auth = _Auth();
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          await service.syncWithServer();
          await _answer(source, 'newer');
          service.scheduleSync(delay: Duration.zero);
          await _until(() async => (await _outbox())['revision'] == 2);
          service.dispose();
          final restartedSource = ProgressDataSource();
          await restartedSource.init();
          final restarted = _service(auth, restartedSource);
          await restarted.syncWithServer();
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(requests.length, 1);
          expect((await _outbox())['acknowledgedRevision'], 0);
          await _until(_acknowledged);
          expect(requests.length, 2);
          expect(
            (_payload(requests.last)['progress'] as Map)['questionProgressAb'],
            contains('newer'),
          );
          expect(
            await restartedSource.isQuestionAnswered(
              'first',
              TicketCategory.ab,
            ),
            isTrue,
          );
          expect(
            await restartedSource.isQuestionAnswered(
              'newer',
              TicketCategory.ab,
            ),
            isTrue,
          );
        },
        () => MockClient((request) async {
          requests.add(request);
          return requests.length == 1
              ? http.Response('{}', 503, headers: {'retry-after': '1'})
              : _echo(request);
        }),
      );
    },
  );

  test(
    '401 keeps the queue without retrying on every new answer; a new session resumes it',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'first');
      final auth = _Auth();
      var requests = 0;
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          await service.syncWithServer();
          expect((await _outbox())['blocked'], isTrue);
          await _answer(source, 'second');
          service.scheduleSync(delay: Duration.zero);
          await service.syncWithServer();
          await service.syncWithServer();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          expect(requests, 1);
          expect((await _outbox())['acknowledgedRevision'], 0);
          auth.account('google_a');
          await _until(_acknowledged);
          expect(requests, 2);
        },
        () => MockClient(
          (request) async =>
              ++requests == 1 ? http.Response('{}', 401) : _echo(request),
        ),
      );
    },
  );

  test(
    'a late upload cannot import or acknowledge another account and signout stops timers',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'device');
      final auth = _Auth(), held = Completer<http.Response>();
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          final old = service.syncWithServer();
          await _until(() => requests.isNotEmpty);
          auth.account('google_b');
          await _until(() => requests.length == 2);
          expect(_payload(requests.last)['userId'], 'google_b');
          expect(
            requests.last.headers['authorization'],
            'Bearer fixture-google_b',
          );
          held.complete(
            _echo(
              requests.first,
              progress: {
                'questionProgressAb': {
                  'foreign_reply': {
                    'answeredAt': DateTime.now().toIso8601String(),
                    'isCorrect': true,
                  },
                },
              },
            ),
          );
          await old;
          expect(
            await source.isQuestionAnswered('foreign_reply', TicketCategory.ab),
            isFalse,
          );
          expect((await _outbox('google_a'))['acknowledgedRevision'], 0);
          auth.account(null);
          final count = requests.length;
          await Future<void>.delayed(const Duration(milliseconds: 120));
          expect(requests.length, count);
          expect(
            (await _outbox('google_b'))['revision'],
            greaterThan(
              (await _outbox('google_b'))['acknowledgedRevision'] as int,
            ),
          );
          service.dispose();
        },
        () => MockClient((request) {
          requests.add(request);
          return requests.length == 1
              ? held.future
              : Future.value(http.Response('{}', 503));
        }),
      );
    },
  );

  test(
    'reset during an upload cannot resurrect old progress and is delivered in the follow-up',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'old');
      final auth = _Auth(), held = Completer<http.Response>();
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          final first = service.syncWithServer();
          await _until(() => requests.length == 1);
          await source.resetAllProgress();
          await _answer(source, 'after-reset');
          service.scheduleSync(delay: Duration.zero);
          await _until(() async => (await _outbox())['revision'] == 2);
          held.complete(_echo(requests.first));
          await first;
          await _until(_acknowledged);
          expect(requests.length, 2);
          final sent = _payload(requests.last)['progress'] as Map;
          expect(sent['resetAt'], greaterThan(0));
          expect(sent['questionProgressAb'], isNot(contains('old')));
          expect(sent['questionProgressAb'], contains('after-reset'));
          expect(
            await source.isQuestionAnswered('old', TicketCategory.ab),
            isFalse,
          );
          expect(
            await source.isQuestionAnswered('after-reset', TicketCategory.ab),
            isTrue,
          );
        },
        () => MockClient((request) {
          requests.add(request);
          return requests.length == 1
              ? held.future
              : Future.value(_echo(request));
        }),
      );
    },
  );

  test(
    'restoring an older pending snapshot merges the newer local reset instead of rolling it back',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'old');
      final auth = _Auth();
      var calls = 0;
      await http.runWithClient(
        () async {
          final oldService = _service(auth, source);
          await oldService.syncWithServer();
          oldService.dispose();
          // Simulate process death after the normal local write, before its outbox
          // capture. The previous pending upload still describes the old state.
          await source.resetAllProgress();
          await _answer(source, 'new');
          final restored = ProgressDataSource();
          await restored.init();
          final service = _service(auth, restored);
          await service.syncWithServer();
          await _until(_acknowledged);
          expect(
            await restored.isQuestionAnswered('old', TicketCategory.ab),
            isFalse,
          );
          expect(
            await restored.isQuestionAnswered('new', TicketCategory.ab),
            isTrue,
          );
        },
        () {
          return MockClient(
            (request) async =>
                ++calls == 1 ? http.Response('{}', 503) : _echo(request),
          );
        },
      );
    },
  );

  test(
    'malformed or non-ok success responses cannot acknowledge progress',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'q');
      final auth = _Auth();
      var calls = 0;
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          await service.syncWithServer();
          expect((await _outbox())['acknowledgedRevision'], 0);
          await _until(_acknowledged);
          expect(calls, 3);
        },
        () => MockClient((request) async {
          calls++;
          return switch (calls) {
            1 => http.Response('not json', 200),
            2 => http.Response('{"ok":false,"progress":{}}', 200),
            _ => _echo(request),
          };
        }),
      );
    },
  );

  test(
    'pause cancels retries, foreground resumes, and dispose leaves no future attempt',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'q');
      final auth = _Auth();
      var calls = 0;
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          await service.syncWithServer();
          service.didChangeAppLifecycleState(AppLifecycleState.paused);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(calls, 1);
          service.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await _until(() => calls == 2);
          service.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          expect(calls, 2);
        },
        () => MockClient((_) async {
          calls++;
          return http.Response('{}', 503);
        }),
      );
    },
  );

  test(
    'a late pull after account switch cannot import its old account snapshot',
    () async {
      final source = ProgressDataSource();
      await source.init();
      final auth = _Auth(), held = Completer<http.Response>();
      var pulls = 0;
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          final pull = service.pullFromServer();
          await _until(() => pulls == 1);
          auth.account(null);
          held.complete(
            http.Response(
              jsonEncode({
                'ok': true,
                'progress': {
                  'questionProgressAb': {
                    'late': {
                      'answeredAt': DateTime.now().toIso8601String(),
                      'isCorrect': true,
                    },
                  },
                },
              }),
              200,
            ),
          );
          await pull;
          expect(
            await source.isQuestionAnswered('late', TicketCategory.ab),
            isFalse,
          );
        },
        () => MockClient((_) {
          pulls++;
          return held.future;
        }),
      );
    },
  );

  test(
    'import guard stops later garage and streak writes after an awaited boundary',
    () async {
      final source = ProgressDataSource();
      await source.init();
      final prefs = await SharedPreferences.getInstance();
      await source.importProgressSnapshot({
        'game': {'bestScore': 999, 'garageCorrect': 100, 'vehicle': 'foreign'},
        'streak': {'current': 20, 'longest': 20},
      }, stillCurrent: () => (prefs.getInt('game_best_score') ?? 0) != 999);
      expect(prefs.getInt('game_best_score'), 999);
      expect(prefs.getInt('game_garage_correct') ?? 0, 0);
      expect(prefs.getString('game_vehicle'), isNull);
      expect(source.exportProgressSnapshot()['streak']['current'], 0);
    },
  );

  test(
    'an edit accepted during an awaited import is never acknowledged by that older reply',
    () async {
      final source = _ControlledImportSource();
      await source.init();
      await _answer(source, 'first');
      final auth = _Auth(),
          entered = Completer<void>(),
          release = Completer<void>();
      final requests = <http.Request>[];
      source.beforeImport = () async {
        source.beforeImport = null;
        entered.complete();
        await release.future;
      };
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          final old = service.syncWithServer();
          await entered.future;
          await _answer(source, 'during-import');
          service.scheduleSync(delay: Duration.zero);
          await _until(() async => (await _outbox())['revision'] == 2);
          release.complete();
          await old;
          await _until(_acknowledged);
          expect(requests.length, 2);
          expect(
            (_payload(requests.last)['progress'] as Map)['questionProgressAb'],
            contains('during-import'),
          );
          expect(
            await source.isQuestionAnswered('during-import', TicketCategory.ab),
            isTrue,
          );
        },
        () => MockClient((request) async {
          requests.add(request);
          return _echo(request);
        }),
      );
    },
  );

  test(
    'a temporary local import failure retains pending progress and retries without blocking the session',
    () async {
      final source = _ControlledImportSource();
      await source.init();
      await _answer(source, 'local');
      final auth = _Auth();
      var calls = 0;
      source.beforeImport = () async {
        source.beforeImport = null;
        throw StateError('fixture local persistence unavailable');
      };
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          await service.syncWithServer();
          expect((await _outbox())['blocked'], isFalse);
          expect((await _outbox())['acknowledgedRevision'], 0);
          await _until(_acknowledged);
          expect(calls, 2);
          expect(
            await source.isQuestionAnswered('local', TicketCategory.ab),
            isTrue,
          );
        },
        () => MockClient((request) async {
          calls++;
          return _echo(request);
        }),
      );
    },
  );

  test(
    'a failed actual preference acknowledgement retains the pending revision and later edits still upload',
    () async {
      final source = ProgressDataSource();
      await source.init();
      await _answer(source, 'first');
      final auth = _Auth();
      final backend = SharedPreferencesStorePlatform.instance;
      final failing = _FailOneAcknowledgement(backend);
      SharedPreferencesStorePlatform.instance = failing;
      addTearDown(() => SharedPreferencesStorePlatform.instance = backend);
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          final service = _service(
            auth,
            source,
            base: const Duration(milliseconds: 100),
            cap: const Duration(milliseconds: 100),
          );
          await service.syncWithServer();
          expect(failing.failedWrites, 1);
          expect(failing.retainedAtFailure!['acknowledgedRevision'], 0);
          expect(
            failing.retainedAtFailure!['snapshot']['questionProgressAb'],
            contains('first'),
          );
          expect((await _outbox())['acknowledgedRevision'], 0);
          expect((await _outbox())['blocked'], isFalse);
          await _answer(source, 'after-write-failure');
          service.scheduleSync(delay: Duration.zero);
          await _until(_acknowledged);
          expect(requests.length, 2);
          expect(
            (_payload(requests.last)['progress'] as Map)['questionProgressAb'],
            contains('after-write-failure'),
          );
        },
        () => MockClient((request) async {
          requests.add(request);
          return _echo(request);
        }),
      );
    },
  );

  test(
    'a failed first restoration retries before capturing and preserves progress held only in the outbox',
    () async {
      final source = _ControlledImportSource();
      await source.init();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'progress_sync_outbox_v1:google_a',
        jsonEncode({
          'version': 1,
          'revision': 7,
          'acknowledgedRevision': 6,
          'snapshot': {
            'questionProgressAb': {
              'outbox-only': {
                'answeredAt': DateTime.now().toIso8601String(),
                'isCorrect': true,
              },
            },
          },
          'failures': 0,
          'nextAttemptAt': 0,
          'blocked': false,
        }),
      );
      var imports = 0;
      source.beforeImport = () async {
        if (++imports == 1) {
          throw StateError('fixture first restoration unavailable');
        }
      };
      await _answer(source, 'local-before-restore');
      final auth = _Auth(), requests = <http.Request>[];
      await http.runWithClient(
        () async {
          final service = _service(auth, source);
          service.scheduleSync(delay: Duration.zero);
          await _until(_acknowledged);
          expect(imports, greaterThanOrEqualTo(2));
          expect(requests.length, 1);
          expect(
            (_payload(requests.single)['progress']
                as Map)['questionProgressAb'],
            contains('outbox-only'),
          );
          expect(
            (_payload(requests.single)['progress']
                as Map)['questionProgressAb'],
            contains('local-before-restore'),
          );
          expect(
            await source.isQuestionAnswered('outbox-only', TicketCategory.ab),
            isTrue,
          );
        },
        () => MockClient((request) async {
          requests.add(request);
          return _echo(request);
        }),
      );
    },
  );
}
