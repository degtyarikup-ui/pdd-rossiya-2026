import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

final reviewPromptServiceProvider = Provider<ReviewPromptService>(
  (ref) => ReviewPromptService.instance,
);

/// One shared, installation-local counter for completed question sets and city
/// rides. Only completions 1 and 10 can request a review, regardless of score.
/// The store decides whether to show a prompt and never reports a submitted review.
class ReviewPromptService {
  ReviewPromptService._()
    : _platform = (() => defaultTargetPlatform),
      _store = (() => StoreConfig.current),
      _isWeb = kIsWeb,
      _enabled = !kDebugMode,
      _isAvailable = InAppReview.instance.isAvailable,
      _requestReview = InAppReview.instance.requestReview,
      _pluginTimeout = const Duration(seconds: 2);

  @visibleForTesting
  ReviewPromptService.forTesting({
    required TargetPlatform platform,
    AppStore store = AppStore.googlePlay,
    bool isWeb = false,
    required Future<bool> Function() isAvailable,
    required Future<void> Function() requestReview,
    Duration pluginTimeout = const Duration(seconds: 2),
  }) : _platform = (() => platform),
       _store = (() => store),
       _isWeb = isWeb,
       _enabled = true,
       _isAvailable = isAvailable,
       _requestReview = requestReview,
       _pluginTimeout = pluginTimeout;

  static final instance = ReviewPromptService._();
  static const _countKey = 'review_prompt_completions_v1';
  static const _legacyRequestedKey = 'review_prompt_requested';
  final TargetPlatform Function() _platform;
  final AppStore Function() _store;
  final bool _isWeb;
  final bool _enabled;
  final Future<bool> Function() _isAvailable;
  final Future<void> Function() _requestReview;
  final Duration _pluginTimeout;
  Future<void> _tail = Future.value();

  bool get _supported =>
      _enabled &&
      !_isWeb &&
      (_platform() == TargetPlatform.iOS ||
          (_platform() == TargetPlatform.android &&
              _store() == AppStore.googlePlay));

  /// Saves the completion BEFORE invoking any native code. A skipped, failed or
  /// suppressed request consumes its milestone too: never retry on later visits.
  /// Callers must invoke this once per actual completion, never from build().
  /// [readyToRequest] waits for a stable, visible result screen when necessary.
  Future<void> onCompleted({Future<bool> Function()? readyToRequest}) {
    if (!_supported) return Future.value();
    _tail = _tail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          _pluginTimeout,
        );
        final previous = (prefs.getInt(_countKey) ?? 0).clamp(0, 10);
        if (previous >= 10) return;
        final count = previous + 1;
        if (!await prefs.setInt(_countKey, count).timeout(_pluginTimeout)) {
          return;
        }
        if (count != 1 && count != 10) return;
        // An older release already spent this installation's first request.
        if (count == 1 && (prefs.getBool(_legacyRequestedKey) ?? false)) return;
        if (readyToRequest != null && !await readyToRequest()) return;
        if (!await _isAvailable().timeout(_pluginTimeout)) return;
        // Availability may return after the player has left the result screen.
        if (readyToRequest != null && !await readyToRequest()) return;
        // Google completes on dismissal; Apple completes on submission of the
        // request. A bounded wait also lets results appear beneath a still-open
        // native prompt. Never infer dismissal or a written review from this.
        await _requestReview().timeout(_pluginTimeout);
      } catch (_) {
        // Reviews must never break navigation, saved progress or game results.
      }
    });
    return _tail;
  }
}
