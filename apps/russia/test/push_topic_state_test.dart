import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/push_topic_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'cold restart, account switch and opt-out remove previous account topics',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final calls = <String>[];
      Future<void> sub(String topic) async {
        calls.add('+$topic');
      }

      Future<void> unsub(String topic) async {
        calls.add('-$topic');
      }

      final state = PushTopicState(prefs, 'fixture_');
      var migrations = 0;
      await state.migrate(() async {
        migrations++;
      });
      await state.reconcile(
        {'public', 'account-A'},
        subscribe: sub,
        unsubscribe: unsub,
      );
      final restarted = PushTopicState(prefs, 'fixture_');
      await restarted.migrate(() async {
        migrations++;
      });
      await restarted.reconcile(
        {'public', 'account-B'},
        subscribe: sub,
        unsubscribe: unsub,
      );
      expect(calls, ['+public', '+account-A', '-account-A', '+account-B']);
      expect(migrations, 1);
      await PushTopicState(
        prefs,
        'fixture_',
      ).reconcile({}, subscribe: sub, unsubscribe: unsub);
      expect(PushTopicState(prefs, 'fixture_').current, isEmpty);
      expect(calls, containsAll(['-public', '-account-B']));
    },
  );
  test('failed unsubscribe remains durable for retry after restart', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('fixture_topics_v2', ['account-A']);
    final state = PushTopicState(prefs, 'fixture_');
    await expectLater(
      state.reconcile(
        {},
        subscribe: (_) async {},
        unsubscribe: (_) async {
          throw StateError('offline');
        },
      ),
      throwsStateError,
    );
    expect(state.current, {'account-A'});
    final calls = <String>[];
    await PushTopicState(prefs, 'fixture_').reconcile(
      {},
      subscribe: (_) async {},
      unsubscribe: (topic) async {
        calls.add(topic);
      },
    );
    expect(calls, ['account-A']);
    expect(state.current, isEmpty);
  });

  test(
    'iOS starts registration before waiting for APNs or rotating FCM',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final state = PushTopicState(prefs, 'ios_');
      final calls = <String>[];
      var registered = false;
      String? apns;
      Future<bool> sync() => state.synchronize(
        enabled: true,
        requiresApns: true,
        topics: {'mobile', 'account'},
        setAutoInitEnabled: (enabled) async {
          registered = enabled;
          calls.add('auto:$enabled');
        },
        getApnsToken: () async {
          expect(registered, isTrue);
          calls.add('apns');
          return apns;
        },
        deleteToken: () async {
          expect(apns, isNotNull);
          calls.add('delete');
        },
        subscribe: (topic) async => calls.add('+$topic'),
        unsubscribe: (topic) async => calls.add('-$topic'),
      );

      // APNs arrives asynchronously. No FCM operation is legal before it does.
      expect(await sync(), isFalse);
      expect(calls, ['auto:true', 'apns']);
      expect(state.needsMigration, isTrue);
      apns = 'apns-fixture';
      expect(await sync(), isTrue);
      expect(calls, [
        'auto:true',
        'apns',
        'auto:true',
        'apns',
        'delete',
        '+mobile',
        '+account',
      ]);
      expect(state.current, {'mobile', 'account'});
      calls.clear();
      expect(await sync(), isTrue);
      expect(calls, ['auto:true', 'apns']);
    },
  );

  test(
    'fresh opt-out does not request APNs or create a delivery token',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final calls = <String>[];
      expect(
        await PushTopicState(prefs, 'off_').synchronize(
          enabled: false,
          requiresApns: true,
          topics: {'ignored'},
          setAutoInitEnabled: (enabled) async => calls.add('auto:$enabled'),
          getApnsToken: () async => throw StateError('must not request APNs'),
          deleteToken: () async => throw StateError('must not rotate FCM'),
          subscribe: (_) async => throw StateError('must not subscribe'),
          unsubscribe: (_) async => throw StateError('no subscriptions'),
        ),
        isFalse,
      );
      expect(calls, ['auto:false']);
    },
  );

  test('opt-out removes subscribed topics after disabling auto-init', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ios_topic_schema', 2);
    await prefs.setStringList('ios_topics_v2', ['mobile', 'account']);
    final calls = <String>[];
    final state = PushTopicState(prefs, 'ios_');
    expect(
      await state.synchronize(
        enabled: false,
        requiresApns: true,
        topics: {'ignored'},
        setAutoInitEnabled: (enabled) async => calls.add('auto:$enabled'),
        getApnsToken: () async => 'apns-fixture',
        deleteToken: () async => throw StateError('already migrated'),
        subscribe: (_) async => throw StateError('must not subscribe'),
        unsubscribe: (topic) async => calls.add('-$topic'),
      ),
      isFalse,
    );
    expect(calls, ['auto:false', '-mobile', '-account']);
    expect(state.current, isEmpty);
  });

  test('Android subscribes without requesting an APNs token', () async {
    final prefs = await SharedPreferences.getInstance();
    final state = PushTopicState(prefs, 'android_');
    final calls = <String>[];
    expect(
      await state.synchronize(
        enabled: true,
        requiresApns: false,
        topics: {'android'},
        setAutoInitEnabled: (enabled) async => calls.add('auto:$enabled'),
        getApnsToken: () async => throw StateError('Android has no APNs'),
        deleteToken: () async => calls.add('delete'),
        subscribe: (topic) async => calls.add('+$topic'),
        unsubscribe: (topic) async => calls.add('-$topic'),
      ),
      isTrue,
    );
    expect(calls, ['auto:true', 'delete', '+android']);
  });
}
