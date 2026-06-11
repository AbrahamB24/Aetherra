import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerStats {
  final int    games;
  final double avgRounds;
  final int    unitsLost;
  final int    totalStrLost;
  final String? favouriteArmy;

  const PlayerStats({
    required this.games,
    required this.avgRounds,
    required this.unitsLost,
    required this.totalStrLost,
    required this.favouriteArmy,
  });

  static const empty = PlayerStats(
    games: 0, avgRounds: 0, unitsLost: 0,
    totalStrLost: 0, favouriteArmy: null);
}

class StatsService {
  static final _sb = Supabase.instance.client;

  static Future<PlayerStats> load() async {
    final user = _sb.auth.currentUser;
    if (user == null) return PlayerStats.empty;

    final rows = await _sb
        .from('game_sessions')
        .select('game_data')
        .eq('user_id', user.id);

    if (rows.isEmpty) return PlayerStats.empty;

    int totalRounds     = 0;
    int unitsLost       = 0;
    int totalStrLost    = 0;
    final armyCounts    = <String, int>{};

    for (final row in rows) {
      final rawData = row['game_data'];
      final data = rawData is String
          ? (jsonDecode(rawData) as Map<String, dynamic>? ?? {})
          : (rawData as Map<String, dynamic>? ?? {});
      totalRounds += (data['round'] as num? ?? 1).toInt();

      final armyName = data['armyName'] as String?;
      if (armyName != null && armyName.isNotEmpty) {
        armyCounts[armyName] = (armyCounts[armyName] ?? 0) + 1;
      }

      for (final raw in (data['units'] as List? ?? [])) {
        final u      = raw as Map<String, dynamic>;
        final maxCon = (u['maxCon']     as num? ?? 0).toInt();
        final curCon = (u['currentCon'] as num? ?? 0).toInt();
        totalStrLost += (maxCon - curCon).clamp(0, maxCon);
        if (u['eliminatedOnRound'] != null) unitsLost++;
      }
    }

    final favArmy = armyCounts.isEmpty
        ? null
        : (armyCounts.entries.reduce((a, b) => a.value >= b.value ? a : b)).key;

    return PlayerStats(
      games:         rows.length,
      avgRounds:     totalRounds / rows.length,
      unitsLost:     unitsLost,
      totalStrLost:  totalStrLost,
      favouriteArmy: favArmy,
    );
  }
}
