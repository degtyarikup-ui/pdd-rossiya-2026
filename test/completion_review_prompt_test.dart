import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/presentation/widgets/completion_review_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('requests after route transition, once despite result rebuilds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final navigator = GlobalKey<NavigatorState>();
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    var requests = 0;
    late MaterialPageRoute<void> route;
    AnimationStatus? requestedDuring;
    final review = ReviewPromptService.forTesting(
      platform: TargetPlatform.iOS,
      isAvailable: () async => true,
      requestReview: () async {
        requests++;
        requestedDuring = route.animation!.status;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reviewPromptServiceProvider.overrideWithValue(review)],
        child: MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      ),
    );
    route = MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: revision,
        builder: (_, value, _) => CompletionReviewPrompt(
          child: Scaffold(body: Text('Result $value')),
        ),
      ),
    );
    unawaited(navigator.currentState!.push(route));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(requests, 0);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(requestedDuring, AnimationStatus.completed);
    revision.value++;
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Result 1'), findsOneWidget);
  });

  testWidgets('closing the result during availability cancels a late request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final availability = Completer<bool>();
    var requests = 0;
    final navigator = GlobalKey<NavigatorState>();
    final review = ReviewPromptService.forTesting(
      platform: TargetPlatform.iOS,
      isAvailable: () => availability.future,
      requestReview: () async {
        requests++;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reviewPromptServiceProvider.overrideWithValue(review)],
        child: MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const CompletionReviewPrompt(
            child: Scaffold(body: Text('Result')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    availability.complete(true);
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });
}
