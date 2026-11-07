import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/notifier_api.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String? normalizeReferralCode(Object? value) {
  if (value is! String || value.length > 64) return null;
  final code = value.trim();
  return RegExp(r'^[A-Za-z0-9]{3,32}$').hasMatch(code)
      ? code.toUpperCase()
      : null;
}

/// Accept a code or a link issued by the app. Other URLs are not codes.
String? referralCodeFromInput(String value) {
  final code = normalizeReferralCode(value);
  if (code != null) return code;
  if (value.length > 512) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.authority != 'pdd-drive.app' ||
      uri.path != '/app/') {
    return null;
  }
  return normalizeReferralCode(uri.queryParameters['ref']);
}

class ReferralInfo {
  final String code;
  String get link =>
      Uri.https('pdd-drive.app', '/app/', {'ref': code}).toString();
  final int invitedCount;
  final int rewardDays;
  final bool hasUsedReferral;
  final String? referralCodeUsed;
  final int friendBonusDays;
  final int inviterBonusDays;

  const ReferralInfo({
    required this.code,
    this.invitedCount = 0,
    this.rewardDays = 0,
    this.hasUsedReferral = false,
    this.referralCodeUsed,
    this.friendBonusDays = 2,
    this.inviterBonusDays = 2,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> json) => ReferralInfo(
    code:
        normalizeReferralCode(json['code']) ??
        (throw const FormatException('Invalid invitation code')),
    invitedCount: (json['invitedCount'] as int?) ?? 0,
    rewardDays: (json['rewardDays'] as int?) ?? 0,
    hasUsedReferral: json['hasUsedReferral'] == true,
    referralCodeUsed: normalizeReferralCode(json['referralCodeUsed']),
    friendBonusDays: (json['friendBonusDays'] as int?) ?? 2,
    inviterBonusDays: (json['inviterBonusDays'] as int?) ?? 2,
  );

  ReferralInfo withClaim(String code) => ReferralInfo(
    code: this.code,
    invitedCount: invitedCount,
    rewardDays: rewardDays,
    hasUsedReferral: true,
    referralCodeUsed: code,
    friendBonusDays: friendBonusDays,
    inviterBonusDays: inviterBonusDays,
  );
}

enum ReferralClaimStatus {
  success,
  selfReferral,
  ineligible,
  unavailable,
  expired,
  notStarted,
  exhausted,
  alreadyClaimed,
  notFound,
  invalidCode,
  unauthenticated,
  rateLimited,
  pending,
  error,
}

class ReferralClaimResult {
  final ReferralClaimStatus status;
  final int daysAdded;
  final bool isReferral;

  const ReferralClaimResult({
    required this.status,
    this.daysAdded = 0,
    this.isReferral = true,
  });
}

class ReferralService extends ChangeNotifier {
  static final ReferralService instance = ReferralService._();
  static const _pendingKey = 'pending_referral_code';
  final _auth = AuthService.instance;

  ReferralService._() {
    _scope = _currentScope;
    _auth.addListener(_onAuthChanged);
  }

  ({String id, int revision})? get _currentScope {
    final id = _auth.currentUser?.id;
    return id != null && _auth.hasServerSession
        ? (id: id, revision: _auth.accountRevision)
        : null;
  }

  late ({String id, int revision})? _scope;
  ReferralInfo? _info;
  String? _confirmedCode;
  ReferralInfo? get info => _scope == _currentScope ? _info : null;
  Future<ReferralInfo?>? _fetch;
  bool get loading => _fetch != null;
  Future<ReferralClaimResult>? _claim;
  bool get claiming => _claim != null;

  String? _pendingCode;
  String? get pendingCode => _pendingCode;

  Future<void> init({String? incomingCode}) async {
    if (normalizeReferralCode(incomingCode) case final String code) {
      await savePendingCode(code);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingCode ??= normalizeReferralCode(prefs.getString(_pendingKey));
      notifyListeners();
    } catch (_) {}
  }

  void _onAuthChanged() {
    final scope = _currentScope;
    if (scope == _scope) return;
    _scope = scope;
    _info = null;
    _confirmedCode = null;
    _fetch = null;
    _claim = null;
    notifyListeners();
  }

  Future<void> savePendingCode(String value) async {
    final code = referralCodeFromInput(value);
    if (code == null) return;
    _pendingCode = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pendingCode == code) await prefs.setString(_pendingKey, code);
    } catch (_) {}
  }

  Future<void> _clearPendingCode([String? expected]) async {
    if (expected != null && expected != _pendingCode) return;
    _pendingCode = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pendingCode == null) await prefs.remove(_pendingKey);
    } catch (_) {}
  }

  @visibleForTesting
  Future<void> clearPendingCodeForTesting() => _clearPendingCode();

  @visibleForTesting
  void setInfoForTesting(ReferralInfo? info) {
    _info = info;
    notifyListeners();
  }

  @visibleForTesting
  Future<ReferralInfo?> Function({bool forceRefresh})? mockGetReferralInfo;

  Future<ReferralInfo?> getReferralInfo({bool forceRefresh = false}) async {
    final scope = _currentScope;
    if (scope == null) return null;
    if (info != null && !forceRefresh) return info;
    if (_fetch case final inFlight?) return inFlight;
    final headers = _auth.serverHeaders;
    final mock = mockGetReferralInfo;
    final future = Future<ReferralInfo?>(() async {
      try {
        if (mock != null) return await mock(forceRefresh: forceRefresh);
        if (!BackendConfig.hasNotifier && !_auth.isDevSession) return null;
        final resp = await NotifierApi.get(
          '/api/user/referral',
          headers: headers,
        );
        if (resp.statusCode != 200) return null;
        return ReferralInfo.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      } catch (_) {
        return null;
      }
    });
    _fetch = future;
    notifyListeners();
    try {
      final loaded = await future;
      if (_currentScope != scope || _fetch != future) return null;
      if (loaded != null) {
        final code = _confirmedCode;
        _info = code == null ? loaded : loaded.withClaim(code);
      }
      return info;
    } finally {
      if (_fetch == future) {
        _fetch = null;
        notifyListeners();
      }
    }
  }

  Future<ReferralClaimResult> claimCode(String value) async {
    final code = referralCodeFromInput(value);
    if (code == null) return _result(ReferralClaimStatus.invalidCode);
    final scope = _currentScope;
    if (scope == null) {
      await savePendingCode(code);
      return _result(ReferralClaimStatus.unauthenticated);
    }
    if (_claim != null) return _result(ReferralClaimStatus.pending);
    if (!BackendConfig.hasNotifier && !_auth.isDevSession) {
      return _result(ReferralClaimStatus.error);
    }

    final future = _requestClaim(code, _auth.serverHeaders);
    _claim = future;
    notifyListeners();
    try {
      final result = await future;
      if (_currentScope != scope) {
        return _result(ReferralClaimStatus.unauthenticated);
      }
      if (result.status == ReferralClaimStatus.success) {
        if (result.isReferral) {
          _confirmedCode = code;
          _info = _info?.withClaim(code);
        }
        await _clearPendingCode(code);
        if (_currentScope != scope) {
          return _result(ReferralClaimStatus.unauthenticated);
        }
        await PremiumService.instance.checkForGrant();
        if (_currentScope != scope) {
          return _result(ReferralClaimStatus.unauthenticated);
        }
      }
      return result;
    } finally {
      if (_claim == future) {
        _claim = null;
        notifyListeners();
      }
    }
  }

  Future<ReferralClaimResult> _requestClaim(
    String code,
    Map<String, String> headers,
  ) async {
    try {
      // The server keeps a receipt; an explicit retry resumes the same claim.
      final resp = await NotifierApi.post(
        '/api/user/promo/claim',
        idempotent: false,
        headers: headers,
        body: jsonEncode({'code': code}),
      );
      if (resp.statusCode == 401) {
        return _result(ReferralClaimStatus.unauthenticated);
      }
      if (resp.statusCode == 429) {
        return _result(ReferralClaimStatus.rateLimited);
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200 &&
          data['ok'] == true &&
          data['daysAdded'] is int) {
        return ReferralClaimResult(
          status: ReferralClaimStatus.success,
          daysAdded: data['daysAdded'] as int,
          isReferral: data['kind'] != 'promotion',
        );
      }
      return _result(switch (data['error']) {
        'cannot_refer_self' => ReferralClaimStatus.selfReferral,
        'referral_ineligible' => ReferralClaimStatus.ineligible,
        'promo_expired' => ReferralClaimStatus.expired,
        'promo_not_started' => ReferralClaimStatus.notStarted,
        'promo_exhausted' => ReferralClaimStatus.exhausted,
        'promo_inactive' ||
        'promo_already_used' => ReferralClaimStatus.unavailable,
        'already_claimed' => ReferralClaimStatus.alreadyClaimed,
        'code_not_found' || 'inviter_not_found' => ReferralClaimStatus.notFound,
        'invalid_code' => ReferralClaimStatus.invalidCode,
        'referral_pending' => ReferralClaimStatus.pending,
        _ => ReferralClaimStatus.error,
      });
    } catch (_) {
      return _result(ReferralClaimStatus.error);
    }
  }

  static ReferralClaimResult _result(ReferralClaimStatus status) =>
      ReferralClaimResult(status: status);
}
