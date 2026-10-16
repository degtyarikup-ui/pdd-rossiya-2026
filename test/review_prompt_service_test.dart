import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<int> requestedAt;
  late int completion;

  ReviewPromptService service({
    TargetPlatform platform = TargetPlatform.android,
    AppStore store = AppStore.googlePlay,
    bool isWeb = false,
    Future<bool> Function()? available,
    Future<void> Function()? request,
  }) => ReviewPromptService.forTesting(
    platform: platform,
    store: store,
    isWeb: isWeb,
    isAvailable: available ?? (() async => true),
    requestReview: request ?? (() async => requestedAt.add(completion)),
    pluginTimeout: const Duration(milliseconds: 50),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requestedAt = [];
    completion = 0;
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform requests only at 1 and 10, persisting across restarts',
      () async {
        var review = service(platform: platform);
        for (completion = 1; completion <= 30; completion++) {
          if (completion == 6 || completion == 11) {
            review = service(platform: platform);
          }
          await review.onCompleted();
        }
        expect(requestedAt, [1, 10]);
      },
    );
  }

  test(
    'concurrent completions cannot lose increments or duplicate requests',
    () async {
      final review = service();
      await Future.wait(List.generate(25, (_) => review.onCompleted()));
      expect(requestedAt, hasLength(2));
      await service().onCompleted();
      expect(requestedAt, hasLength(2));
    },
  );

  test('an old streak request consumes only the first opportunity', () async {
    SharedPreferences.setMockInitialValues({'review_prompt_requested': true});
    final review = service();
    for (completion = 1; completion <= 15; completion++) {
      await review.onCompleted();
    }
    expect(requestedAt, [10]);
  });

  for (final scenario in [
    'unavailable',
    'exception',
    'hung availability',
    'hung request',
  ]) {
    test(
      '$scenario never blocks results or retries the missed milestone',
      () async {
        final available = Completer<bool>();
        final request = Completer<void>();
        var calls = 0;
        final review = service(
          available: () async {
            if (scenario == 'unavailable') return false;
            if (scenario == 'exception') {
              throw PlatformException(code: 'unavailable');
            }
            if (scenario == 'hung availability') return available.future;
            return true;
          },
          request: () {
            calls++;
            return request.future;
          },
        );
        await review.onCompleted();
        await review.onCompleted();
        expect(calls, scenario == 'hung request' ? 1 : 0);
        // A late availability reply must not initiate a native request.
        available.complete(true);
        request.complete();
        await Future<void>.delayed(Duration.zero);
        expect(calls, scenario == 'hung request' ? 1 : 0);
      },
    );
  }

  test(
    'a throwing request does not poison later completion handling',
    () async {
      var calls = 0;
      final review = service(
        request: () async {
          calls++;
          throw MissingPluginException();
        },
      );
      for (var i = 0; i < 20; i++) {
        await review.onCompleted();
      }
      expect(calls, 2);
    },
  );

  test('leaving during availability suppresses a late prompt', () async {
    var current = true;
    final review = service(
      available: () async {
        current = false;
        return true;
      },
    );
    await review.onCompleted(readyToRequest: () async => current);
    current = true;
    await review.onCompleted();
    expect(requestedAt, isEmpty);
  });

  for (final platform in TargetPlatform.values) {
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      continue;
    }
    test(
      '$platform never uses native reviews or consumes milestones',
      () async {
        await service(platform: platform).onCompleted();
        await service().onCompleted();
        expect(requestedAt, hasLength(1));
      },
    );
  }

  test('RuStore shares the same persistent first/tenth limit', () async {
    var review = service(store: AppStore.rustore);
    for (completion = 1; completion <= 30; completion++) {
      if (completion == 6 || completion == 11) {
        review = service(store: AppStore.rustore);
      }
      await review.onCompleted();
    }
    expect(requestedAt, [1, 10]);
  });

  test('switching Android stores does not reset the shared counter', () async {
    for (completion = 1; completion <= 20; completion++) {
      await service(
        store: completion.isEven ? AppStore.rustore : AppStore.googlePlay,
      ).onCompleted();
    }
    expect(requestedAt, [1, 10]);
  });

  test('web never consumes milestones', () async {
    await service(store: AppStore.rustore, isWeb: true).onCompleted();
    await service(platform: TargetPlatform.iOS, isWeb: true).onCompleted();
    await service().onCompleted();
    expect(requestedAt, hasLength(1));
  });
}
