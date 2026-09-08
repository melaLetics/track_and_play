import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../games/controller/provider/games_repository_provider.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import '../../model/achievement_engine.dart';
import '../../model/achievement_status.dart';
import '../../model/badge_definitions.dart';
import '../widgets/badge_tile.dart';

/// Erfolge/Badges des Ich-Spielers - siehe computeAchievements in
/// achievement_engine.dart für die Freischalt-Regeln. Zeigt bewusst
/// ALLE Badges aus dem Katalog (auch gesperrte, ausgegraut) statt nur
/// die bereits freigeschalteten, damit erkennbar ist, was es noch zu
/// erreichen gibt. Rein funktionale Darstellung (Card/Wrap) - die
/// optische Aufbereitung ist laut Nutzer bewusst auf ganz zuletzt
/// verschoben (siehe ARCHITECTURE.md, "Noch zu bauen" Punkt 5).
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfPlayerAsync = ref.watch(selfPlayerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Erfolge')),
      body: selfPlayerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
        data: (self) {
          if (self == null) {
            return const Center(child: Text('Kein Spieler angelegt.'));
          }
          return _AchievementsBody(selfPlayerId: self.id);
        },
      ),
    );
  }
}

const _categoryTitles = {
  BadgeCategory.streak: 'Sieg-Serien',
  BadgeCategory.matches: 'Partien gespielt',
  BadgeCategory.wins: 'Siege',
  BadgeCategory.colorChampion: 'Farbchampion',
  BadgeCategory.weekday: 'Wochentags-Serien',
  BadgeCategory.special: 'Spezial',
};

class _AchievementsBody extends ConsumerWidget {
  final int selfPlayerId;

  const _AchievementsBody({required this.selfPlayerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(selfGameStatsProvider(selfPlayerId));

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Fehler: $error')),
      data: (rows) {
        // Bewusst UNGEFILTERT (kein Gruppen-/Modus-Dropdown wie im
        // Statistik-Dashboard) - Achievements zählen global über alle
        // Partien des Ich-Spielers, mit dem Nutzer abgestimmt.
        final statuses = computeAchievements(rows);
        final unlockedCount = statuses.values.where((s) => s.unlocked).length;

        final byCategory = <BadgeCategory, List<BadgeDefinition>>{};
        for (final badge in allBadges) {
          byCategory.putIfAbsent(badge.category, () => []).add(badge);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '$unlockedCount / ${allBadges.length} Erfolge freigeschaltet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (final category in BadgeCategory.values)
              if (byCategory[category] != null) ...[
                _CategorySection(
                  title: _categoryTitles[category]!,
                  badges: byCategory[category]!,
                  statuses: statuses,
                ),
                const SizedBox(height: 20),
              ],
          ],
        );
      },
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String title;
  final List<BadgeDefinition> badges;
  final Map<String, AchievementStatus> statuses;

  const _CategorySection({
    required this.title,
    required this.badges,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    final unlockedInCategory =
        badges.where((b) => statuses[b.id]?.unlocked ?? false).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title ($unlockedInCategory/${badges.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final badge in badges)
              BadgeTile(
                badge: badge,
                achievedAt: statuses[badge.id]?.achievedAt,
                unlocked: statuses[badge.id]?.unlocked ?? false,
                timesAchieved: statuses[badge.id]?.timesAchieved,
              ),
          ],
        ),
      ],
    );
  }
}
