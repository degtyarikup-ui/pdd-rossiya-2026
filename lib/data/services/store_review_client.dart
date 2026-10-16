import 'package:flutter/foundation.dart';
import 'package:flutter_rustore_review/flutter_rustore_review.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:pdd_app/core/config/store_config.dart';

/// Only the SDK for the current distribution may prepare/show a review prompt.
/// RuStore request() prepares its ReviewInfo; review() is the only UI call.
class StoreReviewClient {
  const StoreReviewClient({required this.platform, required this.store});

  final TargetPlatform platform;
  final AppStore store;

  bool get _supported =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  bool get _ruStore =>
      platform == TargetPlatform.android && store == AppStore.rustore;

  Future<bool> isAvailable() async {
    if (!_supported) return false;
    if (!_ruStore) return InAppReview.instance.isAvailable();
    // Initialize lazily: never start RuStore's manager in the Google Play build.
    // Missing store/account, an existing review or quota exhaustion throw here.
    await RustoreReviewClient.initialize();
    await RustoreReviewClient.request();
    return true;
  }

  Future<void> requestReview() async {
    if (!_supported) return;
    if (_ruStore) {
      await RustoreReviewClient.review();
    } else {
      await InAppReview.instance.requestReview();
    }
  }
}
