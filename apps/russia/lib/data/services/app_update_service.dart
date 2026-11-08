import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>(
  (ref) => AppUpdateService.instance,
);

/// A release verified against the store, rather than an arbitrary admin link.
class AppUpdateOffer {
  final String version, notes, packageId;
  final int build;
  final Uri storeUrl;
  final bool readyToInstall, flexible;
  const AppUpdateOffer({
    required this.version,
    required this.notes,
    required this.packageId,
    required this.build,
    required this.storeUrl,
    this.readyToInstall = false,
    this.flexible = false,
  });
  String get id =>
      '$packageId:$build:${readyToInstall ? 'ready' : 'available'}';
}

/// Numeric store versions, with missing components treated as zero.
/// Invalid/pre-release versions are deliberately not eligible for prompts.
int? compareStoreVersions(String a, String b) {
  final pattern = RegExp(r'^\d{1,6}(\.\d{1,6}){0,3}$');
  if (!pattern.hasMatch(a) || !pattern.hasMatch(b)) return null;
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 4; i++) {
    final comparison = (i < left.length ? left[i] : 0).compareTo(
      i < right.length ? right[i] : 0,
    );
    if (comparison != 0) return comparison;
  }
  return 0;
}

class AppUpdateService {
  AppUpdateService._()
    : _client = http.Client(),
      _platform = defaultTargetPlatform,
      _enabled = !kIsWeb && !kDebugMode,
      _country = CountryConfig.current.code,
      _package = PackageInfo.fromPlatform,
      _iosSystemVersion = (() async =>
          (await DeviceInfoPlugin().iosInfo).systemVersion),
      _now = DateTime.now,
      _launch = ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  @visibleForTesting
  AppUpdateService.forTesting({
    required http.Client client,
    required TargetPlatform platform,
    required Future<PackageInfo> Function() package,
    Future<String> Function()? iosSystemVersion,
    DateTime Function()? now,
    Future<bool> Function(Uri)? launch,
    String country = 'ru',
    bool enabled = true,
  }) : _client = client,
       _platform = platform,
       _enabled = enabled,
       _country = country,
       _package = package,
       _iosSystemVersion = iosSystemVersion ?? (() async => '26.0'),
       _now = now ?? DateTime.now,
       _launch = launch ?? ((_) async => false);

  static final instance = AppUpdateService._();
  static const _channel = MethodChannel('pdd/app_updates');
  final http.Client _client;
  final TargetPlatform _platform;
  final bool _enabled;
  final String _country;
  final Future<PackageInfo> Function() _package;
  final Future<String> Function() _iosSystemVersion;
  final DateTime Function() _now;
  final Future<bool> Function(Uri) _launch;
  final StreamController<void> _changes = StreamController.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<AppUpdateOffer?>? _checking;
  AppUpdateOffer? _offer;
  DateTime? _checkedAt;
  final Set<String> _shownThisSession = {};
  bool _listening = false;
  bool _opening = false;
  int _generation = 0;

  bool get supported =>
      _enabled &&
      (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS);

  void _listen() {
    if (_listening || _platform != TargetPlatform.android) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'downloaded') {
        _generation++;
        _checkedAt = null;
        _offer = null;
        _changes.add(null);
      }
    });
  }

  Future<AppUpdateOffer?> check() {
    if (!supported) return Future.value(null);
    _listen();
    if (_checking != null) return _checking!;
    // A remote release is never served from a stale/offline disk cache.
    // Poll at most hourly, except when Play signals a completed download.
    if (_checkedAt != null &&
        _now().difference(_checkedAt!) < const Duration(hours: 1)) {
      return Future.value(_offer);
    }
    final generation = _generation;
    return _checking = _check()
        .then((offer) {
          _offer = offer;
          _checkedAt = generation == _generation ? _now() : null;
          return offer;
        })
        .whenComplete(() => _checking = null);
  }

  Future<Map<dynamic, dynamic>?> _playCheck() async {
    try {
      return await _channel
          .invokeMapMethod<dynamic, dynamic>('check')
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      return null;
    }
  }

  Future<AppUpdateOffer?> _check() async {
    try {
      final info = await _package();
      if (info.packageName.endsWith('.dev')) return null;
      final installedBuild = int.tryParse(info.buildNumber);
      if (installedBuild == null) return null;
      final platform = _platform == TargetPlatform.android ? 'android' : 'ios';
      if (platform == 'ios' && info.installerStore != 'com.apple') return null;
      // The Play query is independent of server reachability and confirms the
      // release available to THIS account/device (including staged rollouts).
      final playFuture = platform == 'android'
          ? _playCheck()
          : Future<Map<dynamic, dynamic>?>.value(null);
      Map? release;
      try {
        final response = await _client
            .get(
              Uri.parse('${BackendConfig.notifierUrl}/api/app-update').replace(
                queryParameters: {'app': _country, 'platform': platform},
              ),
            )
            .timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map && data['release'] is Map) {
            release = data['release'] as Map;
          }
        }
      } catch (_) {
        /* Play can still check eligible releases offline from our backend. */
      }
      final play = await playFuture;
      // A configured explicit switch applies only to the exact app/platform.
      if (release != null &&
          release['app'] == _country &&
          release['platform'] == platform &&
          release['enabled'] == false) {
        return null;
      }
      final matches =
          release != null &&
          release['enabled'] == true &&
          release['app'] == _country &&
          release['platform'] == platform &&
          release['packageId'] == info.packageName;
      if (platform == 'android') {
        if (play == null || play['downloading'] == true) return null;
        final ready = play['downloaded'] == true;
        final build = play['build'];
        if ((!ready && play['available'] != true) ||
            build is! int ||
            build <= installedBuild) {
          return null;
        }
        final metadata = matches && release['build'] == build;
        return AppUpdateOffer(
          version: metadata && release['version'] is String
              ? release['version']
              : '',
          notes: metadata && release['notes'] is String ? release['notes'] : '',
          packageId: info.packageName,
          build: build,
          storeUrl: Uri.https('play.google.com', '/store/apps/details', {
            'id': info.packageName,
          }),
          readyToInstall: ready,
          flexible: play['flexible'] == true,
        );
      }
      if (!matches) return null;
      final version = release['version'];
      final build = release['build'];
      final store = Uri.tryParse(
        release['storeUrl'] is String ? release['storeUrl'] : '',
      );
      if (version is! String ||
          build is! int ||
          build <= installedBuild ||
          store == null ||
          store.scheme != 'https' ||
          store.host != 'apps.apple.com' ||
          store.userInfo.isNotEmpty ||
          store.hasPort) {
        return null;
      }
      if ((compareStoreVersions(version, info.version) ?? 0) <= 0) return null;
      final id = RegExp(r'/id(\d+)/?$').firstMatch(store.path)?.group(1);
      if (id == null) return null;
      // The public listing must actually match this app and target version.
      // Approval in App Store Connect alone is not sufficient.
      final listing = await _client
          .get(
            Uri.https('itunes.apple.com', '/lookup', {
              'id': id,
              'country': _country,
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (listing.statusCode != 200) return null;
      final data = jsonDecode(listing.body);
      if (data is! Map ||
          data['results'] is! List ||
          (data['results'] as List).length != 1) {
        return null;
      }
      final app = (data['results'] as List).single;
      if (app is! Map ||
          app['bundleId'] != info.packageName ||
          app['version'] != version) {
        return null;
      }
      if (app['minimumOsVersion'] is! String ||
          (compareStoreVersions(
                    await _iosSystemVersion(),
                    app['minimumOsVersion'],
                  ) ??
                  -1) <
              0) {
        return null;
      }
      return AppUpdateOffer(
        version: version,
        notes: release['notes'] is String ? release['notes'] : '',
        packageId: info.packageName,
        build: build,
        storeUrl: store,
      );
    } catch (_) {
      return null;
    } // Optional feature: offline study always works.
  }

  String _shownKey(AppUpdateOffer offer) =>
      'app_update_${_country}_${offer.readyToInstall ? 'ready' : 'available'}';

  Future<bool> shouldShow(AppUpdateOffer offer) async {
    if (_shownThisSession.contains(offer.id)) return false;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_shownKey(offer));
    return last == null ||
        _now().difference(DateTime.fromMillisecondsSinceEpoch(last)) >=
            const Duration(days: 1);
  }

  /// Record actual presentation, including barrier/back dismissal, not checks.
  Future<void> markShown(AppUpdateOffer offer) async {
    _shownThisSession.add(offer.id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_shownKey(offer), _now().millisecondsSinceEpoch);
    } catch (_) {
      /* Keep session suppression if local storage is unavailable. */
    }
  }

  /// Returns false only for an action failure; user cancellation is successful
  /// handling. Completion/restart requires an explicit tap on the ready offer.
  Future<bool> update(AppUpdateOffer offer) async {
    if (_opening) return true;
    _opening = true;
    try {
      if (offer.readyToInstall) {
        return await _channel.invokeMethod<bool>('complete') == true;
      }
      if (_platform == TargetPlatform.android && offer.flexible) {
        try {
          final result = await _channel.invokeMethod<String>('start');
          if (result == 'accepted' || result == 'cancelled') return true;
        } catch (_) {
          /* Fall back to the verified store page. */
        }
      }
      return await _launch(offer.storeUrl);
    } catch (_) {
      return false;
    } finally {
      _opening = false;
    }
  }
}
