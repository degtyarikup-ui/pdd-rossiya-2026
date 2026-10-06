import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/notification_service.dart';

/// Where a notice button / push tap leads.
enum NoticeAction { none, url, tickets, topics, game, feed, settings }

/// A tap on a notice (popup button, banner, push) to be executed by the UI.
class NoticeTap {
  final NoticeAction action;
  final String url;
  const NoticeTap(this.action, [this.url = '']);
  static NoticeTap? fromData(Map<dynamic, dynamic> data) {
    final action = NoticeAction.values.asNameMap()[data['action']];
    if (action == null || action == NoticeAction.none) return null;
    final url = data['actionUrl'] is String ? data['actionUrl'] as String : '';
    if (action == NoticeAction.url && !url.startsWith('https://')) return null;
    return NoticeTap(action, url);
  }
}

class AppNotice {
  final String id, title, body;
  final DateTime expiresAt;

  /// `popup` (modal on home) or `banner` (dismissible card on home).
  final String kind;
  final String imageUrl, emoji, buttonText, dismissText, actionUrl;

  /// `standard` (image on top), `compact` (small icon), `cover` (tall image).
  final String layout;
  final Color? accent;
  final NoticeAction action;
  const AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.expiresAt,
    this.kind = 'popup',
    this.imageUrl = '',
    this.emoji = '',
    this.buttonText = '',
    this.dismissText = '',
    this.actionUrl = '',
    this.layout = 'standard',
    this.accent,
    this.action = NoticeAction.none,
  });

  bool get isBanner => kind == 'banner';
  NoticeTap? get tap => action == NoticeAction.none
      ? null
      : NoticeTap.fromData({'action': action.name, 'actionUrl': actionUrl});

  static String _str(dynamic v, [int max = 500]) =>
      v is String && v.length <= max ? v.trim() : '';

  static Color? parseColor(dynamic v) {
    if (v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) return null;
    return Color(0xFF000000 | int.parse(v.substring(1), radix: 16));
  }

  static AppNotice? parse(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['title'] is! String ||
        value['body'] is! String ||
        value['expiresAt'] is! num) {
      return null;
    }
    final id = value['id'] as String;
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) return null;
    final image = _str(value['imageUrl']);
    final action =
        NoticeAction.values.asNameMap()[value['action']] ?? NoticeAction.none;
    final actionUrl = _str(value['actionUrl']);
    return AppNotice(
      id: id,
      title: value['title'],
      body: value['body'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (value['expiresAt'] as num).toInt(),
      ),
      kind: value['kind'] == 'banner' ? 'banner' : 'popup',
      imageUrl: image.startsWith('https://') ? image : '',
      emoji: _str(value['emoji'], 8),
      buttonText: _str(value['buttonText'], 24),
      dismissText: _str(value['dismissText'], 24),
      layout: const ['standard', 'compact', 'cover'].contains(value['layout'])
          ? value['layout']
          : 'standard',
      accent: parseColor(value['accent']),
      action: action == NoticeAction.url && !actionUrl.startsWith('https://')
          ? NoticeAction.none
          : action,
      actionUrl: actionUrl,
    );
  }
}

/// Remote policy is cached so disabling reminders survives offline launches.
/// Campaigns are never shown from a stale cache: disabled/expired notices must
/// not reappear offline. A failed request leaves existing local reminders alone.
class RemoteNotificationsService {
  RemoteNotificationsService._()
    : _client = http.Client(),
      _userProvider = (() => AuthService.instance.currentUser);
  @visibleForTesting
  RemoteNotificationsService.forTesting({
    required http.Client client,
    UserProfile? Function()? userProvider,
  }) : _client = client,
       _userProvider = userProvider ?? (() => AuthService.instance.currentUser);
  final http.Client _client;
  final UserProfile? Function() _userProvider;
  static final instance = RemoteNotificationsService._();
  static String get platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';

  /// Deterministic FCM topic for a personal account test target (email or ID).
  static String userTopic(String value) {
    final raw = value.trim().toLowerCase();
    if (raw.isEmpty) return '';
    final bytes = utf8.encode(raw).take(64);
    return 'pdd_u_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  String get _prefix => 'notifications_${CountryConfig.current.code}_';
  SharedPreferences? _prefs;
  Future<void>? _refreshing;
  List<AppNotice> _messages = [];
  final Map<String, bool> _config = {
    'pushEnabled': false,
    'popupEnabled': true,
    'streakEnabled': true,
    'gameEnabled': true,
  };
  bool _firebaseReady = false;
  bool _pushOptIn = false;
  bool? _subscriptionState;
  Set<String> _subscribedUserTopics = {};
  bool _authListening = false;
  String _lastAuthKey = '';
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// Active, not-dismissed banners for the home screen.
  final ValueNotifier<List<AppNotice>> banners = ValueNotifier(const []);
  final StreamController<NoticeTap> _taps = StreamController.broadcast();

  /// Actions requested by taps on pushes (incl. cold start). The UI executes them.
  Stream<NoticeTap> get taps => _taps.stream;
  NoticeTap? _pendingTap;

  /// A tap that arrived before the UI subscribed (cold start from a push).
  NoticeTap? takePendingTap() {
    final tap = _pendingTap;
    _pendingTap = null;
    return tap;
  }

  void _emitTap(NoticeTap? tap) {
    if (tap == null) return;
    if (_taps.hasListener) {
      _taps.add(tap);
    } else {
      _pendingTap = tap;
    }
  }

  void _handleTapPayload(String payload) {
    try {
      final data = jsonDecode(payload);
      if (data is Map) _emitTap(NoticeTap.fromData(data));
    } catch (_) {
      /* ignore malformed payloads */
    }
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _pushOptIn = _prefs!.getBool('${_prefix}pushOptIn') ?? false;
    final cached = _prefs!.getString('${_prefix}config');
    if (cached != null) {
      try {
        _applyConfig(jsonDecode(cached));
      } catch (_) {
        /* use defaults */
      }
    }
    if (!_authListening && identical(this, instance)) {
      _authListening = true;
      final u = _userProvider();
      _lastAuthKey = '${u?.id ?? ''}|${u?.email ?? ''}';
      AuthService.instance.addListener(() {
        final cur = _userProvider();
        final key = '${cur?.id ?? ''}|${cur?.email ?? ''}';
        if (key != _lastAuthKey) {
          _lastAuthKey = key;
          unawaited(refresh());
        }
      });
    }
    StreakNotifier.instance.adminTapHandler = _handleTapPayload;
    await StreakNotifier.instance.applyRemotePolicy(
      streakEnabled: _config['streakEnabled']!,
      gameEnabled: _config['gameEnabled']!,
    );
    try {
      final launch = await StreakNotifier.instance.launchPayload();
      if (launch != null && launch.startsWith('{')) _handleTapPayload(launch);
    } catch (_) {
      /* optional */
    }
  }

  void _applyConfig(dynamic value) {
    if (value is! Map) return;
    for (final key in _config.keys.toList()) {
      if (value[key] is bool) _config[key] = value[key];
    }
  }

  Future<void> refresh() => _refreshing ??= _fetch().whenComplete(() {
    _refreshing = null;
    _publishBanners();
  });

  void _publishBanners() {
    final seen = _prefs?.getStringList('${_prefix}seen') ?? const [];
    final now = DateTime.now();
    banners.value = _config['popupEnabled'] == true
        ? _messages
              .where(
                (m) =>
                    m.isBanner &&
                    m.expiresAt.isAfter(now) &&
                    !seen.contains(m.id),
              )
              .take(3)
              .toList()
        : const [];
  }

  /// Hides a banner forever on this device.
  Future<void> dismissBanner(String id) async {
    await markSeen(id);
    _publishBanners();
  }

  Future<void> _fetch() async {
    try {
      if (_prefs == null) await init();
      final user = _userProvider();
      final uri = Uri.parse('${BackendConfig.notifierUrl}/api/notifications')
          .replace(
            queryParameters: {
              'app': CountryConfig.current.code,
              'platform': platform,
              if (user != null && user.id.trim().isNotEmpty)
                'userId': user.id.trim(),
              if (user != null && user.email.trim().isNotEmpty)
                'email': user.email.trim(),
            },
          );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        _messages = [];
        return;
      }
      final data = jsonDecode(response.body);
      if (data is! Map || data['config'] is! Map || data['messages'] is! List) {
        _messages = [];
        return;
      }
      _applyConfig(data['config']);
      await _prefs!.setString('${_prefix}config', jsonEncode(_config));
      await StreakNotifier.instance.applyRemotePolicy(
        streakEnabled: _config['streakEnabled']!,
        gameEnabled: _config['gameEnabled']!,
      );
      _messages = (data['messages'] as List)
          .map(AppNotice.parse)
          .whereType<AppNotice>()
          .toList();
      try {
        await _syncPushSubscriptions();
      } catch (_) {
        /* Remote push setup is independent of popups. */
      }
    } catch (_) {
      _messages = []; /* Keep offline training and cached policy usable. */
    }
  }

  AppNotice? get nextNotice {
    if (_config['popupEnabled'] != true) return null;
    final seen = _prefs?.getStringList('${_prefix}seen') ?? [];
    for (final message in _messages) {
      if (!message.isBanner &&
          message.expiresAt.isAfter(DateTime.now()) &&
          !seen.contains(message.id)) {
        return message;
      }
    }
    return null;
  }

  Future<void> markSeen(String id) async {
    if (_prefs == null) await init();
    final seen = _prefs!.getStringList('${_prefix}seen') ?? [];
    if (!seen.contains(id)) seen.add(id);
    await _prefs!.setStringList(
      '${_prefix}seen',
      seen.length > 500 ? seen.sublist(seen.length - 500) : seen,
    );
  }

  Future<void> setPushConsent(
    bool enabled, {
    bool requestPermission = true,
  }) async {
    if (_prefs == null) await init();
    _pushOptIn = enabled;
    await _prefs!.setBool('${_prefix}pushOptIn', enabled);
    if (enabled && requestPermission) {
      await StreakNotifier.instance.requestPermission();
    }
    try {
      await _syncPushSubscriptions();
    } catch (_) {
      /* Retry at next refresh. */
    }
  }

  Future<void> _syncPushSubscriptions() async {
    // Missing configuration must never initialize an unrelated Firebase project
    // or break builds/country variants that have no push integration yet.
    if (kIsWeb ||
        !const bool.fromEnvironment('ENABLE_REMOTE_PUSH') ||
        (!_pushOptIn && !_firebaseReady)) {
      return;
    }
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const sender = String.fromEnvironment('FIREBASE_SENDER_ID');
    const androidApp = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    const iosApp = String.fromEnvironment('FIREBASE_IOS_APP_ID');
    final appId = platform == 'ios' ? iosApp : androidApp;
    if (project.isEmpty || apiKey.isEmpty || sender.isEmpty || appId.isEmpty) {
      return;
    }
    if (!_firebaseReady) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: platform == 'ios'
              ? const String.fromEnvironment('FIREBASE_IOS_API_KEY')
              : apiKey,
          appId: appId,
          messagingSenderId: sender,
          projectId: project,
          iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
        ),
      );
      _firebaseReady = true;
      await StreakNotifier.instance.prepareAdminChannel();
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _foregroundSub ??= FirebaseMessaging.onMessage.listen((message) {
        final note = message.notification;
        if (_pushOptIn && _config['pushEnabled'] == true && note != null) {
          unawaited(_showForeground(message));
        }
      });
      _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _emitTap(NoticeTap.fromData(message.data)),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _emitTap(NoticeTap.fromData(initial.data));
    }
    final messaging = FirebaseMessaging.instance;
    _tokenRefreshSub ??= messaging.onTokenRefresh.listen((_) {
      _subscriptionState = null;
      _subscribedUserTopics = {};
      unawaited(_syncPushSubscriptions().catchError((Object _) {}));
    });
    if (platform == 'ios' && await messaging.getAPNSToken() == null) return;
    final permission = await messaging.getNotificationSettings();
    final enabled =
        _pushOptIn &&
        _config['pushEnabled'] == true &&
        (permission.authorizationStatus == AuthorizationStatus.authorized ||
            permission.authorizationStatus == AuthorizationStatus.provisional);
    final user = _userProvider();
    final desiredUserTopics = enabled && user != null
        ? (<String>{userTopic(user.id), userTopic(user.email)}..remove(''))
        : <String>{};
    if (_subscriptionState == enabled &&
        setEquals(_subscribedUserTopics, desiredUserTopics)) {
      return;
    }
    if (_subscriptionState != enabled) {
      await messaging.setAutoInitEnabled(enabled);
      // Exact country/platform audience; guests can also receive opt-in messages.
      for (final topic in [
        'pdd_mobile',
        'pdd_${CountryConfig.current.code}_$platform',
      ]) {
        if (enabled) {
          await messaging.subscribeToTopic(topic);
        } else {
          await messaging.unsubscribeFromTopic(topic);
        }
      }
      _subscriptionState = enabled;
    }
    for (final oldTopic in _subscribedUserTopics.difference(desiredUserTopics)) {
      await messaging.unsubscribeFromTopic(oldTopic);
    }
    for (final newTopic in desiredUserTopics.difference(_subscribedUserTopics)) {
      await messaging.subscribeToTopic(newTopic);
    }
    _subscribedUserTopics = desiredUserTopics;
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final note = message.notification!;
    final data = message.data;
    Uint8List? image;
    final url =
        (data['imageUrl'] as String?) ??
        note.android?.imageUrl ??
        note.apple?.imageUrl;
    if (url != null && url.startsWith('https://')) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 &&
            response.bodyBytes.length <= 2 * 1024 * 1024) {
          image = response.bodyBytes;
        }
      } catch (_) {
        /* show without image */
      }
    }
    await StreakNotifier.instance.showAdminMessage(
      note.title ?? '',
      note.body ?? '',
      data['campaignId'] ?? '',
      image: image,
      accent: AppNotice.parseColor(data['accent']),
      payload: jsonEncode({
        'action': data['action'] ?? 'none',
        'actionUrl': data['actionUrl'] ?? '',
      }),
    );
  }
}
