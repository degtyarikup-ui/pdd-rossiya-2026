import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/notifier_api.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/browser_info_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/browser_info_web.dart';

class ReferralInfo {
  final String code;
  final String link;
  final int invitedCount;
  final int rewardDays;
  final bool hasUsedReferral;
  final String? referredBy;
  final String? referralCodeUsed;
  final int friendBonusDays;
  final int inviterBonusDays;

  const ReferralInfo({
    required this.code,
    required this.link,
    this.invitedCount = 0,
    this.rewardDays = 0,
    this.hasUsedReferral = false,
    this.referredBy,
    this.referralCodeUsed,
    this.friendBonusDays = 1,
    this.inviterBonusDays = 2,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> json) {
    return ReferralInfo(
      code: json['code'] as String? ?? '',
      link: json['link'] as String? ?? '',
      invitedCount: (json['invitedCount'] as num?)?.toInt() ?? 0,
      rewardDays: (json['rewardDays'] as num?)?.toInt() ?? 0,
      hasUsedReferral: json['hasUsedReferral'] == true,
      referredBy: json['referredBy'] as String?,
      referralCodeUsed: json['referralCodeUsed'] as String?,
      friendBonusDays: (json['friendBonusDays'] as num?)?.toInt() ?? 1,
      inviterBonusDays: (json['inviterBonusDays'] as num?)?.toInt() ?? 2,
    );
  }

  ReferralInfo copyWith({
    String? code,
    String? link,
    int? invitedCount,
    int? rewardDays,
    bool? hasUsedReferral,
    String? referredBy,
    String? referralCodeUsed,
    int? friendBonusDays,
    int? inviterBonusDays,
  }) {
    return ReferralInfo(
      code: code ?? this.code,
      link: link ?? this.link,
      invitedCount: invitedCount ?? this.invitedCount,
      rewardDays: rewardDays ?? this.rewardDays,
      hasUsedReferral: hasUsedReferral ?? this.hasUsedReferral,
      referredBy: referredBy ?? this.referredBy,
      referralCodeUsed: referralCodeUsed ?? this.referralCodeUsed,
      friendBonusDays: friendBonusDays ?? this.friendBonusDays,
      inviterBonusDays: inviterBonusDays ?? this.inviterBonusDays,
    );
  }
}

enum ReferralClaimStatus {
  success,
  selfReferral,
  alreadyClaimed,
  notFound,
  invalidCode,
  unauthenticated,
  error,
}

class ReferralClaimResult {
  final ReferralClaimStatus status;
  final int daysAdded;
  final String? message;

  const ReferralClaimResult({
    required this.status,
    this.daysAdded = 0,
    this.message,
  });
}

class ReferralService extends ChangeNotifier {
  static final ReferralService instance = ReferralService._internal();
  static const _pendingKey = 'pending_referral_code';

  ReferralService._internal() {
    AuthService.instance.addListener(_onAuthChanged);
  }

  @visibleForTesting
  ReferralService.forTesting();

  ReferralInfo? _info;
  ReferralInfo? get info => _info;

  bool _loading = false;
  bool get loading => _loading;

  String? _pendingCode;
  String? get pendingCode => _pendingCode;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingCode = prefs.getString(_pendingKey);

      final webCode = takeReferralParam();
      if (webCode != null && webCode.isNotEmpty) {
        _pendingCode = webCode.trim().toUpperCase();
        await prefs.setString(_pendingKey, _pendingCode!);
      }

      if (AuthService.instance.isAuthenticated && _pendingCode != null) {
        await checkPendingReferral();
      }
    } catch (e) {
      debugPrint('ReferralService init error: $e');
    }
  }

  void _onAuthChanged() {
    if (AuthService.instance.isAuthenticated) {
      if (_pendingCode != null) {
        checkPendingReferral();
      }
      getReferralInfo(forceRefresh: true);
    } else {
      _info = null;
      notifyListeners();
    }
  }

  Future<void> savePendingCode(String code) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return;
    _pendingCode = clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingKey, clean);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _clearPendingCode() async {
    _pendingCode = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
    } catch (_) {}
    notifyListeners();
  }

  Future<ReferralInfo?> getReferralInfo({bool forceRefresh = false}) async {
    if (!AuthService.instance.isAuthenticated ||
        !AuthService.instance.hasServerSession) {
      return null;
    }
    if (_info != null && !forceRefresh) return _info;
    if (!BackendConfig.hasNotifier) return null;

    _loading = true;
    notifyListeners();

    try {
      final resp = await NotifierApi.get(
        '/api/user/referral',
        headers: AuthService.instance.serverHeaders,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _info = ReferralInfo.fromJson(data);
      }
    } catch (e) {
      debugPrint('ReferralService.getReferralInfo error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
    return _info;
  }

  Future<ReferralClaimResult> claimCode(String code) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty || clean.length < 3) {
      return const ReferralClaimResult(status: ReferralClaimStatus.invalidCode);
    }

    if (!AuthService.instance.isAuthenticated ||
        !AuthService.instance.hasServerSession) {
      await savePendingCode(clean);
      return const ReferralClaimResult(
        status: ReferralClaimStatus.unauthenticated,
      );
    }

    if (!BackendConfig.hasNotifier) {
      return const ReferralClaimResult(status: ReferralClaimStatus.error);
    }

    try {
      final resp = await NotifierApi.post(
        '/api/user/referral/claim',
        idempotent: false,
        headers: AuthService.instance.serverHeaders,
        body: jsonEncode({'code': clean}),
      );

      final data = resp.statusCode == 200 || resp.statusCode == 400 || resp.statusCode == 404
          ? jsonDecode(resp.body) as Map<String, dynamic>
          : null;

      if (resp.statusCode == 200) {
        await _clearPendingCode();
        if (_info != null) {
          _info = _info!.copyWith(
            hasUsedReferral: true,
            referralCodeUsed: clean,
          );
        }
        await PremiumService.instance.checkForGrant();
        notifyListeners();
        return ReferralClaimResult(
          status: ReferralClaimStatus.success,
          daysAdded: (data?['daysAdded'] as num?)?.toInt() ?? 1,
        );
      }

      final error = data?['error'] as String? ?? '';
      if (error == 'cannot_refer_self') {
        return const ReferralClaimResult(
          status: ReferralClaimStatus.selfReferral,
        );
      }
      if (error == 'already_claimed') {
        await _clearPendingCode();
        return const ReferralClaimResult(
          status: ReferralClaimStatus.alreadyClaimed,
        );
      }
      if (resp.statusCode == 404 || error == 'code_not_found') {
        return const ReferralClaimResult(status: ReferralClaimStatus.notFound);
      }
      return const ReferralClaimResult(status: ReferralClaimStatus.error);
    } catch (e) {
      debugPrint('ReferralService.claimCode error: $e');
      return const ReferralClaimResult(status: ReferralClaimStatus.error);
    }
  }

  Future<void> checkPendingReferral() async {
    if (_pendingCode == null || !AuthService.instance.isAuthenticated) return;
    final code = _pendingCode!;
    final result = await claimCode(code);
    if (result.status == ReferralClaimStatus.alreadyClaimed ||
        result.status == ReferralClaimStatus.selfReferral) {
      await _clearPendingCode();
    }
  }
}
