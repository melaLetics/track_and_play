import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../achievements/model/achievement_engine.dart';
import '../../../achievements/model/badge_definitions.dart';
import '../../../achievements/view/screen/achievements_screen.dart';
import '../../../achievements/view/widgets/badge_tile.dart';
import '../../../games/controller/provider/games_repository_provider.dart';

/// "Deine letzten Erfolge"-Karte im Home-Dashboard: zeigt die zuletzt
/// freigeschalteten Badges (siehe achievement_engine.dart) mit Link
/// zum vollständigen Erfolge-Screen - auf Nutzerwunsch angelehnt an
/// "LastArchievements" aus mtg_stats_tracker. Zahl der angezeigten
/// Badges bewusst 4 gewählt (Nutzer nannte "drei oder vier" als
/// gleichwertig, siehe ARCHITECTURE.md).
const _maxShown = 4;

class LastAchievementsCard extends ConsumerWidget {
  final int selfPlayerId;

  const LastAchievementsCard({required this.selfPlayerId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(selfGameStatsProvider(selfPlayerId));

    return statsAsync.maybeWhen(
      data: (rows) {
        final statuses = computeAchievements(rows);
        final badgesById = {for (final b in allBadges) b.id: b};

        // Record statt MapEntry<BadgeDefinition, DateTime>, seit auch
        // timesAchieved (nur bei Sieg-/Wochentags-Serien gesetzt,
        // siehe AchievementStatus) mit durchgereicht werden muss.
        final unlocked = <(BadgeDefinition, DateTime, int?)>[];
        for (final entry in statuses.entries) {
          final achievedAt = entry.value.achievedAt;
          if (!entry.value.unlocked || achievedAt == null) continue;
          final badge = badgesById[entry.key];
          if (badge == null) continue;
          unlocked.add((badge, achievedAt, entry.value.timesAchieved));
        }
        unlocked.sort((a, b) => b.$2.compareTo(a.$2));
        final latest = unlocked.take(_maxShown).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Deine letzten Erfolge',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (unlocked.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AchievementsScreen(),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${unlocked.length}'),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (latest.isEmpty)
                  Text(
                    'Spiele Partien und feiere deine ersten Erfolge.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in latest)
                        BadgeTile(
                          badge: entry.$1,
                          achievedAt: entry.$2,
                          timesAchieved: entry.$3,
                        ),
                    ],
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
