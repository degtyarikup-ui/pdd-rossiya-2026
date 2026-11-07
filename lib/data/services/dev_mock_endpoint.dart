import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/referral_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-app mock backend for dev / test builds.
///
/// Allows full testing of referral code generation, claiming, self-referral
/// prevention, duplicate claim prevention, inviter rewards, and Premium grants
/// without requiring live OAuth registrations or Cloudflare worker deployments.
class DevMockEndpoint {
  DevMockEndpoint._();

  static const String prefixToken = 'dev_token_';
  static const String defaultCodeUser1 = 'DEVTEST1';
  static const String defaultCodeUser2 = 'DEVTEST2';
  static const String seedFriendCode = 'FRIEND26';

  static const Map<String, String> defaultCodeOwners = {
    defaultCodeUser1: 'dev_tester_1',
    defaultCodeUser2: 'dev_tester_2',
    seedFriendCode: 'virtual_friend',
  };

  /// Route by the request credential, never by the currently visible account.
  static bool shouldHandle(Map<String, String>? headers) =>
      AuthService.debugSignInAvailable && _extractUserId(headers) != null;

  static String? _extractUserId(Map<String, String>? headers) {
    final auth = headers?['authorization'];
    const prefix = 'Bearer $prefixToken';
    if (auth == null || !auth.startsWith(prefix)) return null;
    final id = auth.substring(prefix.length);
    return RegExp(r'^(dev_|debug_)[a-zA-Z0-9_]{1,48}$').hasMatch(id)
        ? id
        : null;
  }

  static Future<void> _tail = Future.value();

  static Future<http.Response> _serial(
    Future<http.Response> Function() action,
  ) {
    final request = _tail.then((_) => action());
    _tail = request.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return request;
  }

  static String _defaultCodeForUser(String userId) {
    if (userId == 'dev_tester_1' || userId == 'debug_tester') {
      return defaultCodeUser1;
    }
    if (userId == 'dev_tester_2') {
      return defaultCodeUser2;
    }
    final cleaned = userId.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final padded = cleaned.padRight(6, 'X');
    return 'DEV${padded.substring(0, padded.length.clamp(0, 5))}';
  }

  static Future<Map<String, dynamic>> _getUserReferralData(
    SharedPreferences prefs,
    String userId,
  ) async {
    final key = 'dev_mock_referrals_$userId';
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        return {
          ...jsonDecode(raw) as Map<String, dynamic>,
          'friendBonusDays': 2,
        };
      } catch (_) {}
    }
    final code = _defaultCodeForUser(userId);
    final initial = <String, dynamic>{
      'ok': true,
      'code': code,
      'link': 'https://pdd-drive.app/app/?ref=$code',
      'invitedCount': 0,
      'rewardDays': 0,
      'hasUsedReferral': false,
      'referredBy': null,
      'referralCodeUsed': null,
      'friendBonusDays': 2,
      'inviterBonusDays': 2,
    };
    await prefs.setString(key, jsonEncode(initial));
    return initial;
  }

  static Future<void> _saveUserReferralData(
    SharedPreferences prefs,
    String userId,
    Map<String, dynamic> data,
  ) async {
    await prefs.setString('dev_mock_referrals_$userId', jsonEncode(data));
  }

  static Future<Map<String, String>> _getCodeOwners(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString('dev_mock_code_owners');
    final map = <String, String>{...defaultCodeOwners};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          map[entry.key] = entry.value.toString();
        }
      } catch (_) {}
    }
    return map;
  }

  static Future<void> _registerCodeOwner(
    SharedPreferences prefs,
    String code,
    String userId,
  ) async {
    final owners = await _getCodeOwners(prefs);
    owners[code] = userId;
    await prefs.setString('dev_mock_code_owners', jsonEncode(owners));
  }

  static Future<void> _addPremiumDays(
    SharedPreferences prefs,
    String userId,
    int days, {
    String source = 'referral',
  }) async {
    final key = 'dev_mock_premium_$userId';
    final raw = prefs.getString(key);
    DateTime currentExpiry = DateTime.now();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final exp = DateTime.tryParse(
          decoded['premiumExpiresAt'] as String? ?? '',
        );
        if (exp != null && exp.isAfter(currentExpiry)) {
          currentExpiry = exp;
        }
      } catch (_) {}
    }
    final newExpiry = currentExpiry.add(Duration(days: days));
    final data = {
      'isPremium': true,
      'premiumExpiresAt': newExpiry.toIso8601String(),
      'premiumSource': source,
    };
    await prefs.setString(key, jsonEncode(data));
  }

  static Future<Map<String, dynamic>> _getPremiumData(
    SharedPreferences prefs,
    String userId,
  ) async {
    final key = 'dev_mock_premium_$userId';
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final exp = DateTime.tryParse(
          decoded['premiumExpiresAt'] as String? ?? '',
        );
        final isPremium = exp != null && exp.isAfter(DateTime.now());
        return {
          'isPremium': isPremium,
          'premiumExpiresAt': isPremium ? exp.toIso8601String() : null,
          'premiumSource': isPremium
              ? (decoded['premiumSource'] ?? 'referral')
              : null,
        };
      } catch (_) {}
    }
    return {
      'isPremium': false,
      'premiumExpiresAt': null,
      'premiumSource': null,
    };
  }

  /// Handles GET requests for dev mock sessions.
  static Future<http.Response> handleGet(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? query,
  }) => _serial(() async {
    final userId = _extractUserId(headers);
    if (userId == null) return http.Response('{"error":"unauthorized"}', 401);
    final prefs = await SharedPreferences.getInstance();

    if (path == '/api/user/referral') {
      final data = await _getUserReferralData(prefs, userId);
      final code = data['code'] as String? ?? _defaultCodeForUser(userId);
      await _registerCodeOwner(prefs, code, userId);
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/api/user/status') {
      final status = await _getPremiumData(prefs, userId);
      return http.Response(
        jsonEncode(status),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.Response('{"error":"not_found"}', 404);
  });

  /// Handles POST requests for dev mock sessions.
  static Future<http.Response> handlePost(
    String path, {
    Map<String, String>? headers,
    String? body,
  }) => _serial(() async {
    final userId = _extractUserId(headers);
    if (userId == null) return http.Response('{"error":"unauthorized"}', 401);
    final prefs = await SharedPreferences.getInstance();

    if (path == '/api/user/referral/claim' || path == '/api/user/promo/claim') {
      Map<String, dynamic> bodyJson = {};
      try {
        if (body != null && body.isNotEmpty) {
          bodyJson = jsonDecode(body) as Map<String, dynamic>;
        }
      } catch (_) {}

      final cleanCode = normalizeReferralCode(bodyJson['code']);

      if (cleanCode == null) {
        return http.Response(
          jsonEncode({'error': 'invalid_code'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      }

      if (path == '/api/user/promo/claim' && cleanCode == 'PREMIUM7') {
        final receipt = 'dev_mock_promo_${userId}_$cleanCode';
        if (prefs.getBool(receipt) != true) {
          await _addPremiumDays(prefs, userId, 7, source: 'promo');
          await prefs.setBool(receipt, true);
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'kind': 'promotion',
            'daysAdded': 7,
            ...await _getPremiumData(prefs, userId),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final userData = await _getUserReferralData(prefs, userId);
      final userOwnCode = userData['code'] as String?;

      if (userOwnCode == cleanCode) {
        return http.Response(
          jsonEncode({'error': 'cannot_refer_self'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      }

      if (userData['hasUsedReferral'] == true &&
          userData['referralCodeUsed'] == cleanCode) {
        return _claimSuccess(prefs, userId);
      }
      if (userData['hasUsedReferral'] == true) {
        return http.Response(
          jsonEncode({'error': 'already_claimed'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      }

      final createdKey = 'dev_mock_created_$userId';
      final created =
          prefs.getInt(createdKey) ?? DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(createdKey, created);
      if (DateTime.now().millisecondsSinceEpoch - created >
          const Duration(days: 7).inMilliseconds) {
        return http.Response(
          jsonEncode({'error': 'referral_ineligible'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      }
      final owners = await _getCodeOwners(prefs);
      final inviterId = owners[cleanCode];

      if (inviterId == null) {
        return http.Response(
          jsonEncode({'error': 'code_not_found'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }

      if (inviterId == userId) {
        return http.Response(
          jsonEncode({'error': 'cannot_refer_self'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      }

      // 1. Reward friend (current user) +2 days of Premium
      userData['hasUsedReferral'] = true;
      userData['referralCodeUsed'] = cleanCode;
      await _saveUserReferralData(prefs, userId, userData);
      await _addPremiumDays(prefs, userId, 2);

      // 2. Reward inviter if known test user (+1 invite, +2 bonus days)
      if (inviterId != 'virtual_friend') {
        final inviterData = await _getUserReferralData(prefs, inviterId);
        final currentCount =
            (inviterData['invitedCount'] as num?)?.toInt() ?? 0;
        final currentDays = (inviterData['rewardDays'] as num?)?.toInt() ?? 0;
        inviterData['invitedCount'] = currentCount + 1;
        inviterData['rewardDays'] = currentDays + 2;
        await _saveUserReferralData(prefs, inviterId, inviterData);
        await _addPremiumDays(prefs, inviterId, 2);
      }

      return _claimSuccess(prefs, userId);
    }

    if (path == '/api/user/sync') {
      final premium = await _getPremiumData(prefs, userId);
      final current = AuthService.instance.currentUser;
      return http.Response(
        jsonEncode({
          'ok': true,
          'user': {
            'id': userId,
            'name': current?.name ?? 'Тестировщик',
            'email': current?.email ?? '$userId@example.com',
            'provider': current?.provider.name ?? 'google',
          },
          'isPremium': premium['isPremium'],
          'premiumExpiresAt': premium['premiumExpiresAt'],
          'premiumSource': premium['premiumSource'],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/api/user/delete') {
      await prefs.remove('dev_mock_referrals_$userId');
      await prefs.remove('dev_mock_premium_$userId');
      return http.Response(
        jsonEncode({'ok': true, 'deleted': userId}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/api/auth/logout') {
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.Response('{"error":"not_found"}', 404);
  });

  static Future<http.Response> _claimSuccess(
    SharedPreferences prefs,
    String userId,
  ) async => http.Response(
    jsonEncode({
      'ok': true,
      'daysAdded': 2,
      'inviterDaysAdded': 2,
      ...await _getPremiumData(prefs, userId),
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  @visibleForTesting
  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where(
          (k) =>
              k.startsWith('dev_mock_referrals_') ||
              k.startsWith('dev_mock_premium_') ||
              k == 'dev_mock_code_owners',
        )
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
