import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/store_review_link.dart';

void main() {
  test(
    'iOS opens the published write-review page even with Android store flag',
    () async {
      const link = StoreReviewLink(
        platform: TargetPlatform.iOS,
        store: AppStore.rustore,
      );
      final calls = <Uri>[];
      expect(
        await link.open(
          launch: (uri) async {
            calls.add(uri);
            return true;
          },
        ),
        isTrue,
      );
      expect(
        calls.single.toString(),
        'https://apps.apple.com/app/id6792369533?action=write-review',
      );
    },
  );

  test(
    'Play uses its verified domain and published package, including dev builds',
    () {
      const link = StoreReviewLink(
        platform: TargetPlatform.android,
        store: AppStore.googlePlay,
      );
      expect(
        link.destinations.single.toString(),
        'https://play.google.com/store/apps/details?id=ru.pdd.pdd_app',
      );
    },
  );

  for (final throws in [false, true]) {
    test(
      'missing RuStore falls back to its web listing (throws=$throws)',
      () async {
        const link = StoreReviewLink(
          platform: TargetPlatform.android,
          store: AppStore.rustore,
        );
        final calls = <Uri>[];
        expect(
          await link.open(
            launch: (uri) async {
              calls.add(uri);
              if (calls.length == 1) {
                if (throws) throw StateError('Store unavailable');
                return false;
              }
              return true;
            },
          ),
          isTrue,
        );
        expect(calls.map((uri) => uri.toString()), [
          'rustore://apps.rustore.ru/app/ru.pdd.pdd_app',
          'https://www.rustore.ru/catalog/app/ru.pdd.pdd_app',
        ]);
      },
    );
  }

  test('web skips native deep links, unavailable launch is reported', () async {
    const link = StoreReviewLink(
      platform: TargetPlatform.android,
      store: AppStore.rustore,
      isWeb: true,
    );
    expect(link.destinations.single.scheme, 'https');
    expect(await link.open(launch: (_) async => false), isFalse);
  });
}
