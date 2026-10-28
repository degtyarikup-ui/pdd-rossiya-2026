import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/services/app_update_service.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/payment_mode.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';

enum InboxItemType {
  /// A message from the admin panel (news, window or banner).
  news,

  /// Premium became active for this account (or was extended).
  premiumStarted,

  /// Premium of this account ran out.
  premiumEnded,

  /// A newer version is published in the store.
  update,

  /// Premium can be paid by SBP in this build and region.
  sbp,
}

class InboxItem {
  final String id;
  final InboxItemType type;
  final DateTime date;

  /// [InboxItemType.news] only.
  final AppNotice? notice;

  /// Premium end date; null for Premium without an end date.
  final DateTime? premiumUntil;

  /// [InboxItemType.update] only.
  final AppUpdateOffer? update;

  const InboxItem({
    required this.id,
    required this.type,
    required this.date,
    this.notice,
    this.premiumUntil,
    this.update,
  });
}

/// The notification inbox next to support in the profile.
///
/// Admin news come from [RemoteNotificationsService]; subscription, update
/// and SBP entries are derived on the device from the state the app already
/// has, so the inbox adds no server writes. Read marks are local.
class NotificationInboxService extends ChangeNotifier {
  NotificationInboxService._()
    : _premium = (() => PremiumService.instance.isPremium),
      _premiumUntil = (() => PremiumService.instance.expiresAt),
      _userId = (() => AuthService.instance.currentUser?.id),
      _sbpAvailable = _defaultSbpAvailable,
      _checkUpdate = (() => AppUpdateService.instance.check()),
      _receivesPush = (() => RemoteNotificationsService.instance.receivesPush),
      _now = DateTime.now;

  @visibleForTesting
  NotificationInboxService.forTesting({
    required bool Function() premium,
    required DateTime? Function() premiumUntil,
    required String? Function() userId,
    Future<bool> Function()? sbpAvailable,
    Future<AppUpdateOffer?> Function()? checkUpdate,
    bool Function()? receivesPush,
    DateTime Function()? now,
  }) : _premium = premium,
       _premiumUntil = premiumUntil,
       _userId = userId,
       _sbpAvailable = sbpAvailable ?? (() async => false),
       _checkUpdate = checkUpdate ?? (() async => null),
       _receivesPush = receivesPush ?? (() => false),
       _now = now ?? DateTime.now;

  static final instance = NotificationInboxService._();

  final bool Function() _premium;
  final DateTime? Function() _premiumUntil;
  final String? Function() _userId;
  final Future<bool> Function() _sbpAvailable;
  final Future<AppUpdateOffer?> Function() _checkUpdate;
  final bool Function() _receivesPush;
  final DateTime Function() _now;

  String get _prefix => 'inbox_${CountryConfig.current.code}_';
  static const _sbpId = 'sbp_payments_v1';
  static const _maxRead = 400;
  static const _maxEvents = 30;

  SharedPreferences? _prefs;
  Future<void>? _initializing;
  bool _listening = false;
  bool _sbp = false;
  DateTime? _sbpCheckedAt;
  AppUpdateOffer? _update;
  List<AppNotice> _news = const [];
  Set<String> _seenNews = const {};
  List<InboxItem> _items = const [];
  Set<String> _read = {};
  Set<String> _homeDismissed = {};

  /// Newest first.
  List<InboxItem> get items => _items;
  bool isRead(String id) => _read.contains(id);
  int get unreadCount => _items.where((i) => !_read.contains(i.id)).length;
  bool get hasUnread => unreadCount > 0;

  /// Unread entries the home screen reminds about: everything unread except
  /// what was already there when the reminder was closed. Windows and banners
  /// show themselves on the home screen, and a push this device received
  /// already reached the lock screen: they keep only the bell's dot.
  int get homeAlertCount => _items
      .where(
        (i) =>
            !_read.contains(i.id) &&
            !_homeDismissed.contains(i.id) &&
            _remindsOnHome(i.notice),
      )
      .length;

  bool _remindsOnHome(AppNotice? n) =>
      n == null || (n.isNews && !(n.push && _receivesPush()));

  /// An admin message seen elsewhere (a banner on the home screen).
  Future<void> markNoticeRead(String noticeId) async {
    final id = 'news_$noticeId';
    if (_prefs == null || _read.contains(id)) return;
    _read.add(id);
    await _saveRead();
    notifyListeners();
  }

  Future<void> _saveRead() {
    final list = _read.toList();
    return _prefs!.setStringList(
      '${_prefix}read',
      list.length > _maxRead ? list.sublist(list.length - _maxRead) : list,
    );
  }

  /// Hides the home reminder until another entry arrives; the bell keeps
  /// its badge.
  Future<void> dismissHomeAlert() async {
    if (_prefs == null) return;
    _homeDismissed.addAll(
      _items.where((i) => !_read.contains(i.id)).map((i) => i.id),
    );
    final list = _homeDismissed.toList();
    await _prefs!.setStringList(
      '${_prefix}home_dismissed',
      list.length > _maxRead ? list.sublist(list.length - _maxRead) : list,
    );
    notifyListeners();
  }

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _read = (_prefs!.getStringList('${_prefix}read') ?? const []).toSet();
    _homeDismissed =
        (_prefs!.getStringList('${_prefix}home_dismissed') ?? const []).toSet();
    if (!_listening && identical(this, instance)) {
      _listening = true;
      final remote = RemoteNotificationsService.instance;
      void onNews() => setNews(remote.inbox.value, remote.seenIds);
      remote.inbox.addListener(onNews);
      onNews();
      PremiumService.instance.addListener(_onAccountOrPremium);
      AuthService.instance.addListener(_onAccountOrPremium);
      AppUpdateService.instance.changes.listen((_) => unawaited(refresh()));
    }
    await _observePremium();
    _rebuild();
    unawaited(refresh());
  }

  void _onAccountOrPremium() {
    if (_prefs == null) return;
    unawaited(_observePremium().then((_) => _refreshSbp()));
  }

  /// Re-checks the store release and SBP availability (both cached upstream).
  Future<void> refresh() async {
    if (_prefs == null) {
      await init();
      return;
    }
    await _observePremium();
    try {
      _update = await _checkUpdate();
    } catch (_) {
      /* Optional: the inbox works offline. */
    }
    await _refreshSbp();
  }

  /// The answer is kept for an hour: Premium and account changes rebuild the
  /// list often, the payment provider status rarely changes.
  Future<void> _refreshSbp() async {
    final checkedAt = _sbpCheckedAt;
    if (!_premium() &&
        (checkedAt == null ||
            _now().difference(checkedAt) >= const Duration(hours: 1))) {
      try {
        _sbp = await _sbpAvailable();
        _sbpCheckedAt = _now();
      } catch (_) {
        _sbp = false; /* Hide the SBP entry when availability is unknown. */
      }
    }
    _rebuild();
  }

  @visibleForTesting
  void setNews(List<AppNotice> news, Set<String> seen) {
    _news = news;
    _seenNews = seen;
    _rebuild();
  }

  /// Subscription start/end history of the signed-in account. The last active
  /// Premium is remembered, so its end is reported even after the server no
  /// longer returns the old date. Signing out is not an end of Premium.
  Future<void> _observePremium() async {
    final prefs = _prefs;
    final user = _userId();
    if (prefs == null || user == null || user.isEmpty) return;
    final stateKey = '${_prefix}premium_state';
    Map<String, dynamic>? state;
    try {
      final raw = prefs.getString(stateKey);
      if (raw != null) state = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      state = null;
    }
    final now = _now();
    final events = _loadEvents();
    final before = events.length;
    if (_premium()) {
      final until = _premiumUntil()?.millisecondsSinceEpoch ?? 0;
      final sameUser = state?['user'] == user;
      final previous = sameUser ? (state?['until'] as num?)?.toInt() : null;
      // A shorter date (refund, correction) is not news for the person.
      final extended =
          previous == null ||
          (previous != 0 && (until == 0 || until > previous));
      if (extended) {
        _addEvent(events, {
          'id': 'premium_on_${user}_$until',
          'type': 'on',
          'user': user,
          'at': now.millisecondsSinceEpoch,
          'until': until,
        });
      }
      if (previous != until) {
        await prefs.setString(
          stateKey,
          jsonEncode({'user': user, 'until': until}),
        );
      }
    } else if (state != null && state['user'] == user) {
      final until = (state['until'] as num?)?.toInt() ?? 0;
      if (until != 0 && now.millisecondsSinceEpoch >= until) {
        _addEvent(events, {
          'id': 'premium_off_${user}_$until',
          'type': 'off',
          'user': user,
          'at': until,
          'until': until,
        });
        await prefs.remove(stateKey);
      }
    }
    if (events.length != before) {
      await prefs.setString('${_prefix}premium_events', jsonEncode(events));
      _rebuild();
    }
  }

  List<Map<String, dynamic>> _loadEvents() {
    try {
      final raw = _prefs?.getString('${_prefix}premium_events');
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((e) => e['id'] is String && e['at'] is num)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _addEvent(List<Map<String, dynamic>> events, Map<String, dynamic> e) {
    if (events.any((x) => x['id'] == e['id'])) return;
    events.add(e);
    if (events.length > _maxEvents) {
      events.removeRange(0, events.length - _maxEvents);
    }
  }

  /// When an entry without its own date was first shown on this device.
  DateTime _firstSeen(String id) {
    final key = '${_prefix}first_$id';
    final stored = _prefs?.getInt(key);
    if (stored != null) return DateTime.fromMillisecondsSinceEpoch(stored);
    final now = _now();
    unawaited(_prefs?.setInt(key, now.millisecondsSinceEpoch));
    return now;
  }

  void _rebuild() {
    if (_prefs == null) return;
    final user = _userId();
    final items = <InboxItem>[
      for (final n in _news)
        InboxItem(
          id: 'news_${n.id}',
          type: InboxItemType.news,
          date: n.createdAt ?? _firstSeen('news_${n.id}'),
          notice: n,
        ),
      for (final e in _loadEvents())
        if (e['user'] == user)
          InboxItem(
            id: e['id'] as String,
            type: e['type'] == 'off'
                ? InboxItemType.premiumEnded
                : InboxItemType.premiumStarted,
            date: DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt()),
            premiumUntil: (e['until'] as num?)?.toInt() == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (e['until'] as num).toInt(),
                  ),
          ),
      if (_update != null)
        InboxItem(
          id: 'update_${_update!.version}',
          type: InboxItemType.update,
          date: _firstSeen('update_${_update!.version}'),
          update: _update,
        ),
      if (_sbp && !_premium())
        InboxItem(
          id: _sbpId,
          type: InboxItemType.sbp,
          date: _firstSeen(_sbpId),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    // A window already shown, a banner already closed or a push opened
    // counts as read.
    for (final n in _news) {
      if (_seenNews.contains(n.id)) _read.add('news_${n.id}');
    }
    _items = items;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    if (_prefs == null || _items.every((i) => _read.contains(i.id))) return;
    _read.addAll(_items.map((i) => i.id));
    await _saveRead();
    notifyListeners();
  }
}

/// SBP is offered on the web and in Android builds where the paywall offers
/// it, and only while the payment provider is connected. Never on iOS.
Future<bool> _defaultSbpAvailable() async {
  if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) return false;
  if (!kIsWeb &&
      !(await currentAndroidPaymentModes()).contains(PaymentMode.sbp)) {
    return false;
  }
  return PremiumService.instance.webPaymentsAvailable();
}
