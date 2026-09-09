import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/premium_granted_dialog.dart';

void main() {
  testWidgets('PremiumGrantedDialog displays correct elements for limited duration', (tester) async {
    final exp = DateTime.now().add(const Duration(days: 30));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PremiumGrantedDialog.show(context, expiresAt: exp),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Вам выдан Premium!'), findsOneWidget);
    expect(find.text('PRO ДОСТУП АКТИВИРОВАН'), findsOneWidget);
    expect(find.text('Отлично, спасибо!'), findsOneWidget);
    expect(find.textContaining('1 месяц'), findsOneWidget);

    // Dismiss
    await tester.tap(find.text('Отлично, спасибо!'));
    await tester.pumpAndSettle();
    expect(find.text('Вам выдан Premium!'), findsNothing);
  });

  testWidgets('PremiumGrantedDialog displays correct elements for lifetime duration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PremiumGrantedDialog.show(context, expiresAt: null),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Вам выдан Premium!'), findsOneWidget);
    expect(find.text('Вам открыт бессрочный доступ навсегда!'), findsOneWidget);
  });
}
