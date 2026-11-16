import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Only this small, account-free snapshot is shared with home screen widgets.
class StreakWidgetService {
  static const channel = MethodChannel('pdd/streak_widget');

  static Map<String, Object?> snapshot(Streak streak, AppLocalizations l10n) =>
      {
        'current': streak.current,
        'longest': streak.longest,
        // A calendar date, never UTC: native widgets age the streak offline.
        'lastActiveDate': streak.lastActiveDate == null
            ? null
            : '${streak.lastActiveDate!.year.toString().padLeft(4, '0')}-'
                  '${streak.lastActiveDate!.month.toString().padLeft(2, '0')}-'
                  '${streak.lastActiveDate!.day.toString().padLeft(2, '0')}',
        'nameLabel': l10n.homeWidgetName,
        'currentLabel': l10n.homeWidgetCurrent,
        'bestLabel': l10n.homeWidgetBest,
        'doneLabel': l10n.homeWidgetDone,
        'continueLabel': l10n.homeWidgetContinue,
        'startLabel': l10n.homeWidgetStart,
      };

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
