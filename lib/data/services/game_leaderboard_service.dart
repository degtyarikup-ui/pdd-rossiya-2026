import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';

/// One row of the weekly game leaderboard.
class GameLeaderboardEntry {
  final int rank;
  final String name;
  final int score;
  final int runs;
  final bool isMe;

  const GameLeaderboardEntry({
    required this.rank,
    required this.name,
    required this.score,
    required this.runs,
    required this.isMe,
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
    );
  }
}

class GameLeaderboard {
  final String week;
  final DateTime? endsAt;
  final int total;
  final List<GameLeaderboardEntry> top;
  final GameLeaderboardEntry? me;

  const GameLeaderboard({
    required this.week,
    required this.endsAt,
    required this.total,
    required this.top,
    required this.me,
  });
}

/// Weekly points race: every finished run adds its score to the player's
/// weekly total on the worker; the board lists the top 100 of the week.
class GameLeaderboardService {
  GameLeaderboardService._();
  static final GameLeaderboardService instance = GameLeaderboardService._();

  Map<String, String> get _headers => AuthService.instance.serverHeaders;

  /// Adds a run's score to this week's total. Silent on any failure: the
  /// game must never depend on the network.
  Future<int?> submitRun(int score) async {
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

  Future<GameLeaderboard?> fetch() async {
    if (!BackendConfig.hasNotifier) return null;
    final user = AuthService.instance.currentUser;
    try {
      final uri = Uri.parse(
        '${BackendConfig.notifierUrl}/api/game/leaderboard',
      ).replace(queryParameters: {if (user != null) 'userId': user.id});
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
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
      );
    } catch (e) {
      debugPrint('GameLeaderboardService.fetch: $e');
      return null;
    }
  }
}
