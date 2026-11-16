import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/services/streak_widget_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<Object?, Object?>>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(StreakWidgetService.channel, (
      call,
    ) async {
      calls.add(Map<Object?, Object?>.from(call.arguments as Map));
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(StreakWidgetService.channel, null);
  });

  test('shares localized counts and a local date without account data', () {
    for (final language in ['ru', 'en', 'kk']) {
      final l10n = lookupAppLocalizations(Locale(language));
      final data = StreakWidgetService.snapshot(
        Streak(
          current: 7,
          longest: 21,
          lastActiveDate: DateTime(2026, 3, 8, 23, 59),
          startDate: DateTime(2026, 3, 2),
          activeDays: const {},
        ),
        l10n,
      );
      expect(data['lastActiveDate'], '2026-03-08');
      expect(data['current'], 7);
      expect(data['longest'], 21);
      expect(data['currentLabel'], l10n.homeWidgetCurrent);
      expect(
        data.keys,
        unorderedEquals([
          'current',
          'longest',
          'lastActiveDate',
          'nameLabel',
          'currentLabel',
          'bestLabel',
          'doneLabel',
          'continueLabel',
          'startLabel',
        ]),
      );
    }
  });

  test(
    'activity, locale, import and reset refresh the native snapshot',
    () async {
      final ds = ProgressDataSource(
        homeWidgetUpdater: StreakWidgetService.update,
      );
      await ds.init();
      await ds.refreshHomeWidget();
      expect(calls.last['current'], 0);
      await ds.recordActivity();
      await ds.refreshHomeWidget();
      expect(calls.last['current'], 1);
      expect(calls.last['longest'], 1);

      await ds.saveAppSettings(const AppSettings(languageCode: 'kk'));
      await ds.refreshHomeWidget();
      expect(
        calls.last['bestLabel'],
        lookupAppLocalizations(const Locale('kk')).homeWidgetBest,
      );

      final remote = ds.exportProgressSnapshot();
      (remote['streak'] as Map)['longest'] = 25;
      await ds.importProgressSnapshot(remote);
      await ds.refreshHomeWidget();
      expect(calls.last['longest'], 25);
      await ds.resetAllProgress();
      await ds.refreshHomeWidget();
      expect(calls.last['current'], 0);
      expect(calls.last['longest'], 0);
      expect(calls.last['lastActiveDate'], isNull);
    },
  );

  test('expired series publishes zero while preserving the record', () async {
    final date = DateTime.now().subtract(const Duration(days: 4));
    SharedPreferences.setMockInitialValues({
      'streak_current': 5,
      'streak_longest': 12,
      'streak_last_active':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    });
    final ds = ProgressDataSource(
      homeWidgetUpdater: StreakWidgetService.update,
    );
    await ds.init();
    await ds.refreshHomeWidget();
    expect(calls.last['current'], 0);
    expect(calls.last['longest'], 12);
  });

  test('native failure does not block progress or later updates', () async {
    messenger.setMockMethodCallHandler(StreakWidgetService.channel, (_) async {
      throw PlatformException(code: 'widget_storage_unavailable');
    });
    final ds = ProgressDataSource(
      homeWidgetUpdater: StreakWidgetService.update,
    );
    await ds.init();
    await ds.recordActivity();
    await ds.refreshHomeWidget();
    expect((await ds.loadStreak()).current, 1);
    messenger.setMockMethodCallHandler(StreakWidgetService.channel, (
      call,
    ) async {
      calls.add(Map<Object?, Object?>.from(call.arguments as Map));
      return null;
    });
    await ds.refreshHomeWidget();
    expect(calls.last['current'], 1);
  });

  test('missing native plugin is harmless on older hosts', () async {
    messenger.setMockMethodCallHandler(StreakWidgetService.channel, null);
    await StreakWidgetService.update(
      Streak.empty(),
      lookupAppLocalizations(const Locale('ru')),
    );
  });
  test(
    'an unexpected updater failure does not poison the serialized queue',
    () async {
      var fail = true;
      final published = <Streak>[];
      final ds = ProgressDataSource(
        homeWidgetUpdater: (streak, _) async {
          if (fail) throw StateError('host temporarily unavailable');
          published.add(streak);
        },
      );
      await ds.init();
      await ds.refreshHomeWidget();
      fail = false;
      await ds.recordActivity();
      await ds.refreshHomeWidget();
      expect(published.last.current, 1);
      await ds.resetAllProgress();
      await ds.refreshHomeWidget();
      expect(published.last.current, 0);
      expect(published.last.longest, 0);
    },
  );
}
