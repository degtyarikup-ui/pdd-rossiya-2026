import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/data/services/store_review_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const play = MethodChannel('dev.britannio.in_app_review');
  final channels = {
    for (final method in ['initialize', 'request', 'review'])
      method: BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.flutter_rustore_review.RustoreReview.$method',
        const StandardMessageCodec(),
      ),
  };
  late List<String> calls;
  late Map<String, Completer<Object?>> pending;
  String? failMethod;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    pending = {};
    failMethod = null;
    messenger.setMockMethodCallHandler(play, (call) async {
      calls.add('play.${call.method}');
      return call.method == 'isAvailable' ? true : null;
    });
    for (final entry in channels.entries) {
      messenger.setMockDecodedMessageHandler(entry.value, (_) async {
        calls.add('rustore.${entry.key}');
        if (pending.containsKey(entry.key)) return pending[entry.key]!.future;
        return failMethod == entry.key
            ? <Object?>['RuStoreNotInstalledException', 'SDK unavailable', null]
            : <Object?>[null];
      });
    }
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(play, null);
    for (final channel in channels.values) {
      messenger.setMockDecodedMessageHandler(channel, null);
    }
  });

  for (final (platform, store) in [
    (TargetPlatform.android, AppStore.googlePlay),
    (TargetPlatform.iOS, AppStore.googlePlay),
    (TargetPlatform.iOS, AppStore.rustore),
  ]) {
    test('$platform/$store never initializes the RuStore manager', () async {
      final client = StoreReviewClient(platform: platform, store: store);
      expect(await client.isAvailable(), isTrue);
      await client.requestReview();
      expect(calls, ['play.isAvailable', 'play.requestReview']);
    });
  }

  ReviewPromptService service() => ReviewPromptService.forTesting(
    platform: TargetPlatform.android,
    store: AppStore.rustore,
    pluginTimeout: const Duration(milliseconds: 50),
  );

  test(
    'real RuStore binding runs initialize/request/review only on 1 and 10',
    () async {
      var review = service();
      for (var completion = 1; completion <= 20; completion++) {
        if (completion == 6 || completion == 11) review = service();
        await review.onCompleted();
      }
      expect(calls, [
        'rustore.initialize',
        'rustore.request',
        'rustore.review',
        'rustore.initialize',
        'rustore.request',
        'rustore.review',
      ]);
    },
  );

  for (final method in channels.keys) {
    test(
      'RuStore error in $method is contained and not retried on completion 2',
      () async {
        failMethod = method;
        final review = service();
        await review.onCompleted();
        final firstCalls = List.of(calls);
        await review.onCompleted();
        expect(calls, firstCalls);
        expect(
          calls,
          channels.keys
              .takeWhile((key) => key != method)
              .followedBy([method])
              .map((key) => 'rustore.$key')
              .toList(),
        );
        expect(calls.any((call) => call.startsWith('play.')), isFalse);
      },
    );
  }

  for (final method in channels.keys) {
    test(
      'hung RuStore $method cannot hold results or cause a late second review',
      () async {
        final reply = Completer<Object?>();
        pending[method] = reply;
        final review = service();
        await review.onCompleted();
        await review.onCompleted();
        expect(
          calls.where((call) => call == 'rustore.review'),
          hasLength(method == 'review' ? 1 : 0),
        );
        reply.complete(<Object?>[null]);
        await Future<void>.delayed(Duration.zero);
        expect(
          calls.where((call) => call == 'rustore.review'),
          hasLength(method == 'review' ? 1 : 0),
        );
      },
    );
  }

  test(
    'leaving while RuStore prepares info never opens a late prompt',
    () async {
      final reply = Completer<Object?>();
      pending['request'] = reply;
      var current = true;
      final completed = service().onCompleted(
        readyToRequest: () async => current,
      );
      // Wait until the SDK is actually preparing ReviewInfo.
      while (!calls.contains('rustore.request')) {
        await Future<void>.delayed(Duration.zero);
      }
      current = false;
      reply.complete(<Object?>[null]);
      await completed;
      expect(calls, ['rustore.initialize', 'rustore.request']);
    },
  );
}
