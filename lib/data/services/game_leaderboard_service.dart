import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One row of the weekly game leaderboard.
class GameLeaderboardEntry {
  final int rank;
  final String name;
  final int score;
  final int runs;
  final bool isMe;
  final bool isPremium;
  final String? avatarUrl;
  final int? dailyEarned;
  final int? dailyLimit;

  const GameLeaderboardEntry({
    required this.rank,
    required this.name,
    required this.score,
    required this.runs,
    required this.isMe,
    this.isPremium = false,
    this.avatarUrl,
    this.dailyEarned,
    this.dailyLimit,
  });

  factory GameLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return GameLeaderboardEntry(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : '—',
      score: (json['score'] as num?)?.toInt() ?? 0,
      runs: (json['runs'] as num?)?.toInt() ?? 0,
      isMe: json['isMe'] == true,
      isPremium: json['isPremium'] == true,
      avatarUrl: json['avatarUrl'] as String?,
      dailyEarned: (json['dailyEarned'] as num?)?.toInt(),
      dailyLimit: (json['dailyLimit'] as num?)?.toInt(),
    );
  }
}

class GameLeaderboard {
  final String week;
  final DateTime? endsAt;
  final int total;
  final List<GameLeaderboardEntry> top;
  final GameLeaderboardEntry? me;

  /// Когда рейтинг получен с сервера (для строки «на HH:MM» без связи).
  final DateTime? fetchedAt;

  /// Показан сохранённый рейтинг: связи с сервером сейчас нет.
  final bool stale;

  const GameLeaderboard({
    required this.week,
    required this.endsAt,
    required this.total,
    required this.top,
    required this.me,
    this.fetchedAt,
    this.stale = false,
  });

  /// Разбор ответа `/api/game/leaderboard`. Не объект — null.
  static GameLeaderboard? parse(
    String body, {
    DateTime? fetchedAt,
    bool stale = false,
  }) {
    final data = jsonDecode(body);
    if (data is! Map) return null;
    final top = (data['top'] as List<dynamic>? ?? [])
        .map(
          (e) => GameLeaderboardEntry.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
    final me = data['me'] is Map
        ? GameLeaderboardEntry.fromJson(
            Map<String, dynamic>.from(data['me'] as Map),
          )
        : null;
    return GameLeaderboard(
      week: data['week'] as String? ?? '',
      endsAt: DateTime.tryParse(data['endsAt'] as String? ?? ''),
      total: (data['total'] as num?)?.toInt() ?? top.length,
      top: top,
      me: me,
      fetchedAt: fetchedAt,
      stale: stale,
    );
  }

  /// Неделя ещё идёт. После итогов сохранённый рейтинг уже не показываем.
  bool isCurrentAt(DateTime now) {
    final end = endsAt;
    return end == null || end.isAfter(now);
  }
}

/// Weekly points race: every finished run adds its score to the player's
/// weekly total on the worker; the board lists the top 100 of the week.
class GameLeaderboardService {
  GameLeaderboardService._();
  static final GameLeaderboardService instance = GameLeaderboardService._();

  static const _cacheKey = 'game_board_cache_v1';

  /// Основной адрес, запасной, снова основной. Первый запрос в сетях с
  /// ограничениями часто теряется, второй обычно проходит.
  static const _attempts = [
    Duration(seconds: 6),
    Duration(seconds: 6),
    Duration(seconds: 8),
  ];

  static String newRunId() =>
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(0x7FFFFFFF).toRadixString(16)}';

  Map<String, String> get _headers => AuthService.instance.serverHeaders;

  /// Adds a run's score to this week's total. Silent on any failure: the
  /// game must never depend on the network.
  Future<int?> submitRun(int score, {required String runId}) async {
    final user = AuthService.instance.currentUser;
    if (user == null ||
        !AuthService.instance.hasServerSession ||
        score <= 0 ||
        !BackendConfig.hasNotifier) {
      return null;
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${BackendConfig.notifierUrl}/api/game/score'),
            headers: _headers,
            body: jsonEncode({
              'userId': user.id,
              'name': user.name,
              'score': score,
              'runId': runId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      return data is Map ? (data['rank'] as num?)?.toInt() : null;
    } catch (e) {
      debugPrint('GameLeaderboardService.submitRun: $e');
      return null;
    }
  }

  /// Reports the change of the current run's score since the last report.
  /// Returns true when the server took it (the caller then advances its
  /// "reported" mark); false keeps the delta for the next attempt.
  Future<bool> reportProgress({
    required String runId,
    required int delta,
    required int runScore,
    required bool newRun,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null ||
        !AuthService.instance.hasServerSession ||
        (delta == 0 && !newRun) ||
        !BackendConfig.hasNotifier) {
      return false;
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${BackendConfig.notifierUrl}/api/game/score'),
            headers: _headers,
            body: jsonEncode({
              'userId': user.id,
              'name': user.name,
              'runId': runId,
              'delta': delta,
              'runScore': runScore,
              'newRun': newRun,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('GameLeaderboardService.reportProgress: $e');
      return false;
    }
  }

  /// Лучшее место игрока за все закрытые недели (null — не был в топ-100
  /// или нет связи). Нужно для ачивки «Покоритель рейтинга».
  Future<int?> fetchBestRank() async {
    final user = AuthService.instance.currentUser;
    if (user == null ||
        !AuthService.instance.hasServerSession ||
        !BackendConfig.hasNotifier) {
      return null;
    }
    try {
      final uri = Uri.parse(
        '${BackendConfig.notifierUrl}/api/game/best',
      ).replace(queryParameters: {'userId': user.id});
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final rank = data is Map ? (data['bestRank'] as num?)?.toInt() : null;
      return rank != null && rank > 0 ? rank : null;
    } catch (e) {
      debugPrint('GameLeaderboardService.fetchBestRank: $e');
      return null;
    }
  }

  /// Рейтинг недели. Если сеть не отвечает, отдаём последний удачный ответ
  /// с его временем, а не ошибку. Ошибка — только когда сохранённого нет.
  Future<GameLeaderboard?> fetch() async {
    if (!BackendConfig.hasNotifier) return null;
    final userId = AuthService.instance.currentUser?.id;
    try {
      final response = await sendWithRetry(
        (host) => http.get(_boardUri(host, userId), headers: _headers),
        hosts: BackendConfig.notifierHosts,
        attempts: _attempts,
      );
      if (response.statusCode == 200) {
        final now = DateTime.now();
        final board = GameLeaderboard.parse(response.body, fetchedAt: now);
        if (board != null) {
          await _remember(userId, response.body, now);
          return board;
        }
      }
    } catch (e) {
      debugPrint('GameLeaderboardService.fetch: $e');
    }
    return lastKnown();
  }

  /// Последний удачный рейтинг этого аккаунта, пока неделя не закончилась.
  Future<GameLeaderboard?> lastKnown() async {
    final userId = AuthService.instance.currentUser?.id;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (saved['userId'] != userId) return null;
      final board = GameLeaderboard.parse(
        saved['body'] as String,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(saved['savedAt'] as int),
        stale: true,
      );
      if (board == null || !board.isCurrentAt(DateTime.now())) return null;
      return board;
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(String? userId, String body, DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'userId': userId,
          'savedAt': now.millisecondsSinceEpoch,
          'body': body,
        }),
      );
    } catch (_) {
      // Без сохранения рейтинг просто не будет показан из памяти.
    }
  }

  Uri _boardUri(String host, String? userId) => Uri.parse(
    '$host/api/game/leaderboard',
  ).replace(queryParameters: {'userId': ?userId});
}
