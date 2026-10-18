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
}
