import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/presentation/widgets/app_navigation_shell.dart';
import 'package:pdd_app/presentation/widgets/question_keyboard_shortcuts.dart';

void main() {
  final items = <AppNavigationItem>[
    (
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: 'Обучение',
    ),
    (icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Профиль'),
  ];
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'web sidebar, phone bar and resize share the same content state',
    (tester) async {
      viewport(tester, const Size(1440, 900));
      final field = GlobalKey();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: AppNavigationShell(
            desktopEnabled: true,
            selectedIndex: 0,
            onSelected: (index) => selected = index,
            items: items,
            child: TextField(key: field, controller: controller),
          ),
        ),
      );
      final state = field.currentState;
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.enterText(find.byKey(field), 'Продолжаю занятие');
      await tester.tap(find.text('Профиль'));
      await tester.pump();
      expect(selected, 1);
      for (final size in [const Size(390, 844), const Size(1440, 900)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(field.currentState, same(state));
        expect(controller.text, 'Продолжаю занятие');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('native tablets retain their bottom navigation', (tester) async {
    viewport(tester, const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: AppNavigationShell(
          desktopEnabled: false,
          selectedIndex: 0,
          onSelected: (_) {},
          items: items,
          child: const SizedBox(),
        ),
      ),
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('fullscreen hides both kinds of navigation', (tester) async {
    viewport(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: AppNavigationShell(
          desktopEnabled: true,
          fullscreen: true,
          selectedIndex: 0,
          onSelected: (_) {},
          items: items,
          child: const SizedBox(),
        ),
      ),
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'digits, numpad and arrows act once; dialogs and text input keep their keys',
    (tester) async {
      final answers = <int>[];
      var previous = 0, next = 0, confirm = 0, exit = 0;
      final navigator = GlobalKey<NavigatorState>();
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: QuestionKeyboardShortcuts(
            enabled: true,
            answerCount: 3,
            onAnswer: answers.add,
            onPrevious: () => previous++,
            onNext: () => next++,
            onConfirm: () => confirm++,
            onExit: () => exit++,
            child: Scaffold(body: TextField(focusNode: field)),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      expect(answers, [0, 2, 1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect([previous, next, confirm], [1, 1, 1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(exit, 1);
      field.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      expect(answers, [0, 2, 1]);
      field.unfocus();
      await tester.pump();
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      expect(answers, [0, 2, 1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(exit, 1, reason: 'Escape belongs to the dialog while it is open');
    },
  );
}
