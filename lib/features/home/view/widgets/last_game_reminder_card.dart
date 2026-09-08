import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../games/controller/provider/games_repository_provider.dart';

/// Kleiner Erinnerungs-Hinweis im Home-Dashboard - entweder wenn der
/// Ich-Spieler noch NIE eine Partie gespielt hat, oder wenn die letzte
/// Partie mindestens einen Tag her ist. Auf Nutzerwunsch angelehnt an
/// "DaysSinceLastGame" aus mtg_stats_tracker (dort nur der zweite
/// Fall, und schon ab Tag 0 statt erst ab Tag 1 wie hier) - der erste
/// Fall ("noch nie gespielt") kam auf eine spätere Nutzerfrage dazu,
/// siehe ARCHITECTURE.md.
class LastGameReminderCard extends ConsumerWidget {
  final int selfPlayerId;

  const LastGameReminderCard({required this.selfPlayerId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(selfGameStatsProvider(selfPlayerId));

    return statsAsync.maybeWhen(
      data: (rows) {
        if (rows.isEmpty) {
          return _buildCard(
            context,
            title: 'Bereit für deine erste Partie?',
            subtitle: 'Du hast noch keine Partie erfasst - leg los!',
          );
        }

        final lastPlayedAt =
            rows.map((r) => r.playedAt).reduce((a, b) => a.isAfter(b) ? a : b);
        final days = _daysSince(lastPlayedAt);
        if (days < 1) return const SizedBox.shrink();

        return _buildCard(
          context,
          title: 'Vermisst du es schon?',
          subtitle:
              'Deine letzte Partie ist schon $days Tag${days == 1 ? '' : 'e'} her.',
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 36, color: scheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _daysSince(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final playedDay = DateTime(date.year, date.month, date.day);
    return today.difference(playedDay).inDays;
  }
}
