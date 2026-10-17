import 'package:shared_preferences/shared_preferences.dart';

/// Installation state survives Dart restarts. Each successful operation is
/// persisted separately so a failed/offline unsubscribe is retried next time.
class PushTopicState {
  PushTopicState(this.prefs, this.prefix);
  final SharedPreferences prefs;
  final String prefix;
  Set<String> get current =>
      (prefs.getStringList('${prefix}topics_v2') ?? []).toSet();
  bool get needsMigration => prefs.getInt('${prefix}topic_schema') != 2;

  Future<void> migrate(Future<void> Function() deleteToken) async {
    if (!needsMigration) return;
    // Old email topics were not recorded locally. Rotating the registration
    // removes those subscriptions without sending email-derived topic names.
    await deleteToken();
    await clear();
    await prefs.setInt('${prefix}topic_schema', 2);
  }

  Future<void> clear() => prefs.setStringList('${prefix}topics_v2', []);

  Future<void> reconcile(
    Set<String> desired, {
    required Future<void> Function(String) subscribe,
    required Future<void> Function(String) unsubscribe,
  }) async {
    final actual = current;
    for (final old in actual.difference(desired)) {
      await unsubscribe(old);
      actual.remove(old);
      await prefs.setStringList('${prefix}topics_v2', actual.toList());
    }
    for (final topic in desired.difference(actual)) {
      await subscribe(topic);
      actual.add(topic);
      await prefs.setStringList('${prefix}topics_v2', actual.toList());
    }
  }
}
