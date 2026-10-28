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

  /// Auto-init starts APNs registration on iOS. Token operations must wait for
  /// that registration; checking APNs before enabling it leaves a fresh install
  /// permanently unable to subscribe. A token refresh retries this operation.
  Future<bool> synchronize({
    required bool enabled,
    required bool requiresApns,
    required Set<String> topics,
    required Future<void> Function(bool) setAutoInitEnabled,
    required Future<String?> Function() getApnsToken,
    required Future<void> Function() deleteToken,
    required Future<void> Function(String) subscribe,
    required Future<void> Function(String) unsubscribe,
  }) async {
    await setAutoInitEnabled(enabled);
    // Do not request or rotate a delivery token on an opted-out installation
    // with no recorded subscriptions. Migration runs when it next opts in.
    if (!enabled && current.isEmpty) return false;
    if (requiresApns && await getApnsToken() == null) return false;
    await migrate(deleteToken);
    await reconcile(
      enabled ? topics : {},
      subscribe: subscribe,
      unsubscribe: unsubscribe,
    );
    return enabled;
  }

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
