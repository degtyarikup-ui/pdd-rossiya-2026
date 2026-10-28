import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final dismiss in [
    'close',
    'background',
    'back',
    'secondary',
    'primary',
  ]) {
    testWidgets(
      'window closed with $dismiss never reopens after refresh or restart',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        const id = 'c069e042-5b7b-40a0-b15e-b80c4444ce1a';
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'config': {'popupEnabled': true},
              'messages': [
                {
                  'id': id,
                  'title': 'Обновление',
                  'body': 'Новости',
                  'expiresAt': DateTime.now()
                      .add(const Duration(days: 1))
                      .millisecondsSinceEpoch,
                  'buttonText': 'Прочитано',
                  'dismissText': 'Позже',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );
        final service = (await tester.runAsync(
          () async => RemoteNotificationsService.forTesting(client: client),
        ))!;
        addTearDown(service.dispose);
        await tester.runAsync(service.refresh);
        expect(service.nextNotice?.id, id);
        bool? accepted;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final notice = await service.takeNextNotice();
                  if (notice != null && context.mounted) {
                    accepted = await AppNoticeDialog.show(context, notice);
                  }
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('open'));
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.byType(AppNoticeDialog), findsOneWidget);
        switch (dismiss) {
          case 'close':
            await tester.tap(find.byIcon(Icons.close_rounded));
          case 'background':
            await tester.tapAt(const Offset(5, 5));
          case 'back':
            await tester.binding.handlePopRoute();
          case 'secondary':
            await tester.tap(find.text('Позже'));
          case 'primary':
            await tester.tap(find.text('Прочитано'));
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(find.byType(AppNoticeDialog), findsNothing);
        expect(accepted, dismiss == 'primary');
        await tester.runAsync(service.refresh);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(AppNoticeDialog), findsNothing);
        expect(
          service.inbox.value.single.id,
          id,
          reason: 'closing the window preserves its inbox entry until expiry',
        );
        final restarted = (await tester.runAsync(
          () async => RemoteNotificationsService.forTesting(client: client),
        ))!;
        addTearDown(restarted.dispose);
        await tester.runAsync(restarted.refresh);
        expect(await restarted.takeNextNotice(), isNull);
      },
    );
  }
  Future<bool?> open(WidgetTester tester, AppNotice notice) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await AppNoticeDialog.show(context, notice),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a window without a button runs its action on tap', (
    tester,
  ) async {
    bool? result;
    final notice = AppNotice(
      id: 'n',
      title: 'Новая версия',
      body: '',
      expiresAt: DateTime(2100),
      button: false,
      action: NoticeAction.tickets,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await AppNoticeDialog.show(context, notice),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Новая версия'), findsOneWidget);
    await tester.tap(find.text('Новая версия'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('a window with only a title shows no empty text', (tester) async {
    await open(
      tester,
      AppNotice(
        id: 'n',
        title: 'Только заголовок',
        body: '',
        expiresAt: DateTime(2100),
        button: false,
      ),
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Text)),
      findsOneWidget,
    );
  });
}
