import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Only this small, account-free snapshot is shared with home screen widgets.
class StreakWidgetService {
  static const channel = MethodChannel('pdd/streak_widget');

  static Map<String, Object?> snapshot(
    Streak streak,
    AppLocalizations l10n, {
    DateTime? now,
  }) {
    final today = Streak.day(now ?? DateTime.now());
    final lastActive = streak.lastActiveDate;
    final lastDay = lastActive == null ? null : Streak.day(lastActive);
    final week = List.generate(7, (i) => Streak.shiftDay(today, i - 6));
    return {
      'current': streak.current,
      'longest': streak.longest,
      // Local calendar dates let the widget roll forward while the app sleeps.
      'lastActiveDate': lastDay == null ? null : _isoDate(lastDay),
      'activeDates': [
        for (final day in week)
          if (day == lastDay || streak.hasActivityOn(day)) _isoDate(day),
      ],
      'locale': l10n.localeName,
      'nameLabel': l10n.homeWidgetName,
      'currentLabel': l10n.homeWidgetCurrent,
      'bestLabel': l10n.homeWidgetBest,
      'doneLabel': l10n.homeWidgetDone,
      'continueLabel': l10n.homeWidgetContinue,
      'startLabel': l10n.homeWidgetStart,
    };
  }

  static String _isoDate(DateTime date) =>
      date.toIso8601String().split('T').first;

  static Future<void> update(Streak streak, AppLocalizations l10n) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await channel
          .invokeMethod<void>('update', snapshot(streak, l10n))
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      // Desktop tests and older native hosts have no widget bridge.
    } on PlatformException catch (error) {
      debugPrint('Streak widget update: ${error.code}');
    } on TimeoutException {
      debugPrint('Streak widget update timed out');
    }
  }
}
