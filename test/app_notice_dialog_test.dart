import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';

void main() {
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
