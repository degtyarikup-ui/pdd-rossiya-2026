import 'package:flutter/foundation.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Explicit user action opens the store, independently of SDK review quotas.
class StoreReviewLink {
  const StoreReviewLink({
    required this.platform,
    required this.store,
    this.isWeb = false,
  });

  final TargetPlatform platform;
  final AppStore store;
  final bool isWeb;

  List<Uri> get destinations {
    const config = CountryConfig.current;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return [
        Uri.parse(
          'https://apps.apple.com/app/id${config.appStoreId}?action=write-review',
        ),
      ];
    }
    if (store == AppStore.rustore) {
      return [
        if (!isWeb && platform == TargetPlatform.android)
          Uri.parse(
            'rustore://apps.rustore.ru/app/${config.androidPackageName}',
          ),
        Uri.parse(
          'https://www.rustore.ru/catalog/app/${config.androidPackageName}',
        ),
      ];
    }
    return [
      Uri.parse(
        'https://play.google.com/store/apps/details?id=${config.androidPackageName}',
      ),
    ];
  }

  Future<bool> open({Future<bool> Function(Uri)? launch}) async {
    final open =
        launch ?? (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    for (final uri in destinations) {
      try {
        if (await open(uri)) return true;
      } catch (_) {
        // A missing native store falls back to its public web listing.
      }
    }
    return false;
  }
}
