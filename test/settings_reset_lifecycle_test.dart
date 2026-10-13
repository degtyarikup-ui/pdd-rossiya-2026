import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedReset extends ProgressDataSource {
  final release = Completer<void>();
  @override
  Future<void> resetAllProgress() async {
    await release.future;
    await super.resetAllProgress();
  }
}

void main() {
  testWidgets(
    'reset completion after closing settings never reads a disposed ref',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      updateAppLocale(const Locale('ru'));
      final data = _DelayedReset();
      await data.init();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [progressDataSourceProvider.overrideWithValue(data)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(appL10n.resetStats), 400);
      await tester.tap(find.text(appL10n.resetStats));
      await tester.pumpAndSettle();
      await tester.tap(find.text(appL10n.reset));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      data.release.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
