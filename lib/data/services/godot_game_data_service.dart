import 'dart:convert';

import 'package:pdd_app/data/services/game_leaderboard_service.dart';

/// Only public display data crosses into Godot; credentials remain in Flutter.
class GodotGameDataService {
  GodotGameDataService._();

  static Future<String> leaderboard() async =>
      jsonEncode(encode(await GameLeaderboardService.instance.fetch()));

  static Map<String, dynamic> encode(GameLeaderboard? board) {
    if (board == null) return {'available': false};
    Map<String, dynamic> row(GameLeaderboardEntry entry) => {
      'rank': entry.rank,
      'name': entry.name,
      'score': entry.score,
      'is_me': entry.isMe,
    };
    final at = board.fetchedAt?.toLocal();
    return {
      'available': true,
      'stale': board.stale,
      'time': at == null
          ? ''
          : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      'top': board.top.take(100).map(row).toList(),
      if (board.me != null) 'me': row(board.me!),
    };
  }
}
