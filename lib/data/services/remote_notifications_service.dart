import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:pdd_app/data/services/notification_service.dart';
import 'package:pdd_app/data/services/push_topic_state.dart';
import 'package:pdd_app/data/services/network_retry.dart';

/// Where a notice button / push tap leads.
enum NoticeAction {
  none,
  url,
  tickets,
  topics,
  game,
  feed,
  settings,
  support,
  premium,
}

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
  final bool persistent;

  /// Earlier test copies replaced by this broadcast for the same recipient.
  final List<String> seenIds;

  /// Publication time; orders the notification inbox.
  final DateTime? createdAt;

  /// `popup` (modal on home), `banner` (dismissible card on home) or `news`
  /// (only listed in the notification inbox).
  final String kind;
  final String imageUrl, emoji, buttonText, dismissText, actionUrl;

  /// `standard`, `compact`, `cover`, or `image` (the picture is the whole
  /// message: a home banner or a window without text).
  final String layout;

  /// Whether a window shows its primary button (banners: the link chip).
  /// Without it the whole message runs the action on tap.
  final bool button;
  final Color? accent;
  final NoticeAction action;

  /// Also sent as a push. A device that receives pushes keeps it in the inbox
  /// only: a window or banner would repeat what the lock screen showed.
  final bool push;
  const AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.expiresAt,
    this.persistent = false,
    this.seenIds = const [],
    this.createdAt,
    this.kind = 'popup',
    this.imageUrl = '',
    this.emoji = '',
    this.buttonText = '',
    this.dismissText = '',
    this.actionUrl = '',
    this.layout = 'standard',
    this.button = true,
    this.accent,
    this.action = NoticeAction.none,
    this.push = false,
  });

  bool get isBanner => kind == 'banner';
  bool get isNews => kind == 'news';
  bool get isImageOnly => layout == 'image';
  bool get isImageBanner => isBanner && isImageOnly;
  bool isActiveAt(DateTime now) => persistent || expiresAt.isAfter(now);
  bool wasSeen(Set<String> seen) =>
      seen.contains(id) || seenIds.any(seen.contains);
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
    final kind = const ['banner', 'news'].contains(value['kind'])
        ? value['kind'] as String
        : 'popup';
    if (value['layout'] == 'image' && !image.startsWith('https://')) {
      return null;
    }
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
      persistent: value['persistent'] == true && kind == 'news',
      seenIds: value['seenIds'] is List
          ? (value['seenIds'] as List)
                .whereType<String>()
                .where((id) => RegExp(r'^[a-f0-9-]{36}$').hasMatch(id))
                .toList()
          : const [],
      createdAt: value['createdAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (value['createdAt'] as num).toInt(),
            )
          : null,
      kind: kind,
      imageUrl: image.startsWith('https://') ? image : '',
      emoji: _str(value['emoji'], 8),
      buttonText: _str(value['buttonText'], 24),
      dismissText: _str(value['dismissText'], 24),
      layout:
          const [
            'standard',
            'compact',
            'cover',
            'image',
          ].contains(value['layout'])
          ? value['layout']
          : 'standard',
      button: value['button'] != false && value['layout'] != 'image',
      accent: parseColor(value['accent']),
      action: action == NoticeAction.url && !actionUrl.startsWith('https://')
          ? NoticeAction.none
          : action,
      actionUrl: actionUrl,
      push: value['push'] == true,
    );
  }
}

/// Remote policy is cached so disabling reminders survives offline launches.
/// Campaigns are never shown from a stale cache: disabled/expired notices must
/// not reappear offline. A failed request leaves existing local reminders alone.
class RemoteNotificationsService {
  RemoteNotificationsService._()
    : _metricsSecret = BackendConfig.notifierSecret,
      _client = http.Client(),
      _now = DateTime.now,
      _userProvider = (() => AuthService.instance.currentUser),
      _receivesPushOverride = null;
  @visibleForTesting
  RemoteNotificationsService.forTesting({
    required http.Client client,
    UserProfile? Function()? userProvider,
    String metricsSecret = BackendConfig.notifierSecret,
    bool? receivesPush,
    DateTime Function()? now,
  }) : _metricsSecret = metricsSecret,
       _client = client,
       _now = now ?? DateTime.now,
       _userProvider = userProvider ?? (() => AuthService.instance.currentUser),
       _receivesPushOverride = receivesPush;
  final bool? _receivesPushOverride;
  final http.Client _client;
  final DateTime Function() _now;
  final String _metricsSecret;
  final UserProfile? Function() _userProvider;
  static final instance = RemoteNotificationsService._();
  static String get platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';

  String get _prefix => 'notifications_${CountryConfig.current.code}_';
  SharedPreferences? _prefs;
  Future<void>? _refreshing;
  Future<void> _metricsTail = Future.value();
  List<AppNotice> _messages = [];
  Timer? _expiryTimer;
  final Set<String> _claimedNotices = {};
  final Map<String, bool> _config = {
    'pushEnabled': false,
    'popupEnabled': true,
    'streakEnabled': true,
    'gameEnabled': true,
  };
  bool _firebaseReady = false;
  bool _pushOptIn = false;
  bool? _subscriptionState;
  Set<String> _authorizedTopics = {};
  Future<void> _pushSync = Future.value();
  bool _authListening = false;
  String _lastAuthKey = '';
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// Active, not-dismissed banners for the home screen.
  final ValueNotifier<List<AppNotice>> banners = ValueNotifier(const []);

  /// Every active message (news, windows, banners) for the notification inbox.
  final ValueNotifier<List<AppNotice>> inbox = ValueNotifier(const []);
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

  /// Runs a notice action from elsewhere in the app (the notification inbox).
  void runTap(NoticeTap tap) => _emitTap(tap);

  /// Admin pushes reach this device: topics subscribed with permission.
  bool get receivesPush => _receivesPushOverride ?? _subscriptionState == true;

  /// A window or banner for this message on the home screen. Campaigns also
  /// sent as a push show one only where the push could not arrive.
  bool _showsOnHome(AppNotice m) => !m.isNews && !(m.push && receivesPush);

  /// Messages already shown as a window, dismissed as a banner or opened
  /// from a push.
  Set<String> get seenIds =>
      (_prefs?.getStringList('${_prefix}seen') ?? const []).toSet();

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
      if (data is Map) _openedPush(data);
    } catch (_) {
      /* ignore malformed payloads */
    }
  }

  /// A push was tapped (system tray, foreground copy or cold start): the
  /// message counts as read and is not shown again as a window or banner.
  void _openedPush(Map<dynamic, dynamic> data) {
    final id = data['campaignId'];
    if (id is String && RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      unawaited(markSeen(id).then((_) => _publishBanners()));
      unawaited(recordNoticeEvent(id, 'click'));
    }
    _emitTap(NoticeTap.fromData(data));
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
          _authorizedTopics = {};
          unawaited(_syncPushSubscriptions().catchError((Object _) {}));
          unawaited(refresh().then((_) => refresh()));
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
    _expiryTimer?.cancel();
    final seen = seenIds;
    final now = _now();
    final active = _messages.where((m) => m.isActiveAt(now)).toList();
    inbox.value = _config['popupEnabled'] == true ? active : const [];
    banners.value = _config['popupEnabled'] == true
        ? active
              .where((m) => m.isBanner && _showsOnHome(m) && !m.wasSeen(seen))
              .take(3)
              .toList()
        : const [];
    final deadlines = active
        .where((m) => !m.persistent)
        .map((m) => m.expiresAt);
    if (_config['popupEnabled'] == true && deadlines.isNotEmpty) {
      final next = deadlines.reduce((a, b) => a.isBefore(b) ? a : b);
      // Bound long delays for web timers (signed 32-bit milliseconds).
      final delay = next.difference(now);
      _expiryTimer = Timer(
        delay > const Duration(days: 1) ? const Duration(days: 1) : delay,
        _publishBanners,
      );
    }
  }

  @visibleForTesting
  void dispose() => _expiryTimer?.cancel();

  /// Hides a banner forever on this device.
  Future<void> dismissBanner(String id) async {
    await markSeen(id);
    _publishBanners();
  }

  Future<void> _fetch() async {
    try {
      if (_prefs == null) await init();
      unawaited(flushMetrics());
      final user = _userProvider();
      final revision = AuthService.instance.accountRevision;
      final query = {
        'app': CountryConfig.current.code,
        'platform': platform,
        'imageBanners': '1',
        'imagePopups': '1',
        'inbox': '1',
        if (platform == 'android')
          'store': StoreConfig.current == AppStore.rustore ? 'rustore' : 'play',
      };
      final response = await sendWithRetry(
        (host) => _client.get(
          Uri.parse('$host/api/notifications').replace(queryParameters: query),
          headers: AuthService.instance.serverHeaders,
        ),
        hosts: BackendConfig.notifierHosts,
        attempts: const [Duration(seconds: 6), Duration(seconds: 6)],
        pause: Duration.zero,
      );
      if (revision != AuthService.instance.accountRevision ||
          user?.id != _userProvider()?.id) {
        _messages = [];
        return;
      }
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
      _authorizedTopics =
          AuthService.instance.hasServerSession && data['pushTopics'] is List
          ? (data['pushTopics'] as List)
                .whereType<String>()
                .where((t) => RegExp(r'^pdd_account_[a-f0-9]{64}$').hasMatch(t))
                .toSet()
          : {};
      await _prefs!.setString('${_prefix}config', jsonEncode(_config));
      await StreakNotifier.instance.applyRemotePolicy(
        streakEnabled: _config['streakEnabled']!,
        gameEnabled: _config['gameEnabled']!,
      );
      _messages = (data['messages'] as List)
          .map(AppNotice.parse)
          .whereType<AppNotice>()
          .toList();
      // Remember the broadcast itself, so pruning an old test on the server
      // cannot make an already-dismissed window reappear later.
      final seen = seenIds;
      for (final message in _messages) {
        if (!seen.contains(message.id) && message.wasSeen(seen)) {
          await markSeen(message.id);
        }
      }
      try {
        await _syncPushSubscriptions();
      } catch (_) {
        /* Remote push setup is independent of popups. */
      }
    } catch (_) {
      _messages = []; /* Keep offline training and cached policy usable. */
    }
  }

  /// A view or tap of a banner, window, push or inbox entry. Queued before
  /// sending; failed requests retry on the next foreground refresh.
  Future<void> recordNoticeEvent(String campaignId, String event) {
    final account = _userProvider()?.id ?? '';
    return _queueMetrics(campaignId, event, account);
  }

  Future<void> flushMetrics() => _queueMetrics(null, null, null);

  Future<void> _queueMetrics(
    String? campaignId,
    String? event,
    String? account,
  ) {
    _metricsTail = _metricsTail.then((_) async {
      try {
        if (_metricsSecret.isEmpty) return;
        _prefs ??= await SharedPreferences.getInstance();
        final now = DateTime.now().millisecondsSinceEpoch;
        final queueKey = '${_prefix}metrics_queue';
        final seenKey = '${_prefix}metrics_seen';
        final queue = (jsonDecode(_prefs!.getString(queueKey) ?? '[]') as List)
            .cast<Map<String, dynamic>>()
            .where(
              (e) =>
                  now - (e['ts'] as int) <
                  const Duration(days: 30).inMilliseconds,
            )
            .toList();
        final seen = _prefs!.getStringList(seenKey) ?? [];
        final key = '$account|$campaignId|$event';
        if (campaignId != null &&
            const ['view', 'click'].contains(event) &&
            !seen.contains(key)) {
          queue.add({
            'campaignId': campaignId,
            'event': event,
            'ts': now,
            'account': account,
          });
          seen.add(key);
        }
        if (queue.length > 500) queue.removeRange(0, queue.length - 500);
        await _prefs!.setString(queueKey, jsonEncode(queue));
        await _prefs!.setStringList(
          seenKey,
          seen.length > 5000 ? seen.sublist(seen.length - 5000) : seen,
        );
        final currentAccount = _userProvider()?.id ?? '';
        final batch = queue
            .where((e) => e['account'] == currentAccount)
            .take(50)
            .toList();
        if (batch.isEmpty) return;
        final headers =
            Map<String, String>.from(AuthService.instance.serverHeaders)
              ..['content-type'] = 'application/json'
              ..['x-install-secret'] = _metricsSecret;
        final installId = await InstallReporter.installationId();
        // Do not attribute a queued event to a different account during sign-in.
        if ((_userProvider()?.id ?? '') != currentAccount) return;
        final response = await sendWithRetry(
          (host) => _client.post(
            Uri.parse('$host/api/notifications/events'),
            headers: headers,
            body: jsonEncode({
              'installId': installId,
              'platform': platform,
              'store': StoreConfig.current == AppStore.rustore
                  ? 'rustore'
                  : 'play',
              'events': batch
                  .map(
                    (e) => {
                      'campaignId': e['campaignId'],
                      'event': e['event'],
                      'ts': e['ts'],
                    },
                  )
                  .toList(),
            }),
          ),
          hosts: BackendConfig.notifierHosts,
          attempts: const [Duration(seconds: 6), Duration(seconds: 6)],
          pause: Duration.zero,
        );
        if (response.statusCode == 200) {
          queue.removeWhere(batch.contains);
          await _prefs!.setString(queueKey, jsonEncode(queue));
        }
      } catch (_) {
        /* Keep durable events for a later refresh. */
      }
    });
    return _metricsTail;
  }

  AppNotice? get nextNotice {
    if (_config['popupEnabled'] != true) return null;
    final seen = seenIds;
    for (final message in _messages) {
      if (!message.isBanner &&
          _showsOnHome(message) &&
          message.isActiveAt(_now()) &&
          !message.wasSeen(seen) &&
          !_claimedNotices.contains(message.id)) {
        return message;
      }
    }
    return null;
  }

  /// Reserve synchronously before persisting: concurrent home checks cannot
  /// open the same window while the first check is awaiting disk I/O.
  Future<AppNotice?> takeNextNotice() async {
    final notice = nextNotice;
    if (notice == null) return null;
    _claimedNotices.add(notice.id);
    await markSeen(notice.id);
    return notice.isActiveAt(_now()) ? notice : null;
  }

  /// Пуш об ответе поддержки пришёл, пока приложение открыто. Задаёт приложение.
  void Function()? onSupportReply;

  /// Личные пуши аккаунта (ответы поддержки) этому устройству доставляются.
  bool get accountPushActive =>
      _subscriptionState == true && _authorizedTopics.isNotEmpty;

  Future<void> markSeen(String id) async {
    if (_prefs == null) await init();
    final seen = _prefs!.getStringList('${_prefix}seen') ?? [];
    if (!seen.contains(id)) seen.add(id);
    await _prefs!.setStringList(
      '${_prefix}seen',
      seen.length > 500 ? seen.sublist(seen.length - 500) : seen,
    );
    inbox.value = List.of(inbox.value);
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

  Future<void> _syncPushSubscriptions({bool resetTopics = false}) {
    _pushSync = _pushSync.catchError((Object _) {}).then((_) async {
      if (resetTopics) await PushTopicState(_prefs!, _prefix).clear();
      await _performPushSync();
    });
    return _pushSync;
  }

  Future<void> _performPushSync() async {
    // Missing configuration must never initialize an unrelated Firebase project
    // or break builds/country variants that have no push integration yet.
    if (kIsWeb || !const bool.fromEnvironment('ENABLE_REMOTE_PUSH')) {
      return;
    }
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const sender = String.fromEnvironment('FIREBASE_SENDER_ID');
    const androidApp = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    const iosApp = String.fromEnvironment('FIREBASE_IOS_APP_ID');
    final appId = platform == 'ios' ? iosApp : androidApp;
    final appApiKey = platform == 'ios'
        ? const String.fromEnvironment('FIREBASE_IOS_API_KEY')
        : apiKey;
    if (project.isEmpty ||
        appApiKey.isEmpty ||
        sender.isEmpty ||
        appId.isEmpty) {
      return;
    }
    if (!_firebaseReady) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: appApiKey,
          appId: appId,
          messagingSenderId: sender,
          projectId: project,
          iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
        ),
      );
      _firebaseReady = true;
      await StreakNotifier.instance.prepareAdminChannel();
      if (_pushOptIn) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      _foregroundSub ??= FirebaseMessaging.onMessage.listen((message) {
        // Ответ поддержки при открытом приложении: его покажет баннер чата,
        // системное уведомление не нужно — только забрать ответ сразу.
        if (message.data['kind'] == 'support_reply') {
          onSupportReply?.call();
          return;
        }
        final note = message.notification;
        if (_pushOptIn && _config['pushEnabled'] == true && note != null) {
          unawaited(_showForeground(message));
        }
      });
      _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _openedPush(message.data),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openedPush(initial.data);
    }
    final messaging = FirebaseMessaging.instance;
    final topicState = PushTopicState(_prefs!, _prefix);
    _tokenRefreshSub ??= messaging.onTokenRefresh.listen((_) {
      _subscriptionState = null;
      // Clear and resubscribe on the same queue as an in-flight migration or
      // subscription. An unawaited clear can otherwise erase the new state.
      unawaited(
        _syncPushSubscriptions(resetTopics: true).catchError((Object _) {}),
      );
    });
    final permission = await messaging.getNotificationSettings();
    final enabled =
        _pushOptIn &&
        _config['pushEnabled'] == true &&
        (permission.authorizationStatus == AuthorizationStatus.authorized ||
            permission.authorizationStatus == AuthorizationStatus.provisional);
    final desiredTopics = enabled
        ? {
            'pdd_mobile',
            'pdd_${CountryConfig.current.code}_$platform',
            ..._authorizedTopics,
          }
        : <String>{};
    _subscriptionState = false;
    _subscriptionState = await topicState.synchronize(
      enabled: enabled,
      requiresApns: platform == 'ios',
      topics: desiredTopics,
      setAutoInitEnabled: messaging.setAutoInitEnabled,
      getApnsToken: messaging.getAPNSToken,
      deleteToken: messaging.deleteToken,
      subscribe: messaging.subscribeToTopic,
      unsubscribe: messaging.unsubscribeFromTopic,
    );
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
        'campaignId': data['campaignId'] ?? '',
        'action': data['action'] ?? 'none',
        'actionUrl': data['actionUrl'] ?? '',
      }),
    );
  }
}
