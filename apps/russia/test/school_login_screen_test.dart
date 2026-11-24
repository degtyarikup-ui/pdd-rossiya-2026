import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/school_login_route.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/school_login_screen.dart';

void main() {
  testWidgets(
    'the selected account and both actions fit a narrow screen at large text size',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthService.instance;
      addTearDown(() => auth.setSessionForTesting());
      updateAppLocale(const Locale('ru'));
      final user = UserProfile(
        id: 'google_test',
        provider: AuthProviderType.google,
        name: 'Анна Александровна Соколова',
        email: 'school.administrator@example.invalid',
        createdAt: DateTime(2026),
      );
      auth.setSessionForTesting(
        user: user,
        token: 'fixture',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SchoolLoginScreen(route: SchoolLoginRoute('a' * 64, 'b' * 64)),
        ),
      );
      await tester.pumpAndSettle();
      final enter = find.widgetWithText(FilledButton, 'Войти в кабинет');
      final change = find.widgetWithText(TextButton, 'Сменить аккаунт');
      expect(find.text(user.email), findsOneWidget);
      expect(find.text(user.name), findsOneWidget);
      expect(tester.getSize(enter).height, greaterThanOrEqualTo(52));
      await tester.ensureVisible(change);
      expect(change.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
