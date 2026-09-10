import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/score_gauge.dart';
import '../../../games/controller/provider/games_repository_provider.dart';
import '../../../stats/model/player_performance_stats.dart';

/// "Dein Player-Score"-Karte im Home-Dashboard - auf Nutzerwunsch als
/// Barometer dargestellt, angelehnt an "PlayerScore"/"Speedometer"
/// aus mtg_stats_tracker (dort für einen anderen, eigenen
/// "Dominance"-Score genutzt). Nutzt hier den bereits für das
/// Statistik-Dashboard vorhandenen `computeEloScore`
/// (player_performance_stats.dart), aber bewusst UNGEFILTERT nach
/// Gruppe/Modus - analog zu den Achievements (siehe
/// achievement_engine.dart), im Unterschied zur filterbaren
/// Elo-Anzeige auf dem Statistik-Tab.
class EloScoreCard extends ConsumerWidget {
  final int selfPlayerId;

  const EloScoreCard({required this.selfPlayerId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(selfGameStatsProvider(selfPlayerId));

    return statsAsync.maybeWhen(
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();

        final elo = computeEloScore(rows);
        final score = elo.score0to100;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Dein Player-Score',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ScoreGauge(score: score, label: eloScoreLabel(score)),
                Text(
                  'Basiert auf ${elo.gamesCounted} '
                  '${elo.gamesCounted == 1 ? 'Partie' : 'Partien'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
