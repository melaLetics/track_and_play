import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../decks/controller/provider/decks_repository_provider.dart';
import '../../controller/provider/random_deck_filter_provider.dart';
import '../../controller/provider/random_deck_provider.dart';
import '../../model/random_deck_filter_state.dart';
import 'random_deck_filter_sheet.dart';

/// "Welches Deck spiele ich heute?"-Karte im Home-Dashboard - auf
/// Nutzerwunsch (mit Filtern) angelehnt an "RandomDeck" aus
/// mtg_stats_tracker. Nutzt bewusst nur die Decks des Ich-Spielers
/// (playerDecksProvider), nicht das mtg_stats-Konzept eines
/// "focusPlayer" - Track & Play hat dafür kein Äquivalent.
class RandomDeckCard extends ConsumerWidget {
  final int selfPlayerId;

  const RandomDeckCard({required this.selfPlayerId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decksAsync = ref.watch(playerDecksProvider(selfPlayerId));

    return decksAsync.maybeWhen(
      data: (decks) {
        if (decks.isEmpty) return const SizedBox.shrink();

        final filter = ref.watch(randomDeckFilterProvider);
        final candidates = filterDecksForRandom(decks, filter);
        final rolledDeck = ref.watch(randomDeckProvider);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Welches Deck spiele ich heute?',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.filter_list),
                      tooltip: 'Filter',
                      onPressed: () {
                        showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (_) => const RandomDeckFilterSheet(),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Zufälliges Deck'),
                  onPressed: candidates.isEmpty
                      ? null
                      : () => ref.read(randomDeckProvider.notifier).roll(candidates),
                ),
                if (filter.hasActiveFilters) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (filter.bracket != null)
                        InputChip(
                          label: Text('Bracket ${filter.bracket}'),
                          onDeleted: () => ref
                              .read(randomDeckFilterProvider.notifier)
                              .setBracket(null),
                        ),
                      if (filter.type != TypeFilter.all)
                        InputChip(
                          label: Text(switch (filter.type) {
                            TypeFilter.precon => 'Precon',
                            TypeFilter.upgraded => 'Precon (aufgewertet)',
                            TypeFilter.homebrew => 'Eigenbau',
                            TypeFilter.all => '',
                          }),
                          onDeleted: () => ref
                              .read(randomDeckFilterProvider.notifier)
                              .setTypeFilter(TypeFilter.all),
                        ),
                      if (filter.proxy != ProxyFilter.all)
                        InputChip(
                          label: Text(switch (filter.proxy) {
                            ProxyFilter.proxyOnly => 'Proxy',
                            ProxyFilter.originalOnly => 'Nur Originalkarten',
                            ProxyFilter.all => '',
                          }),
                          onDeleted: () => ref
                              .read(randomDeckFilterProvider.notifier)
                              .setProxyFilter(ProxyFilter.all),
                        ),
                    ],
                  ),
                ],
                if (candidates.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Keine Decks passen zu diesen Filtern.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ] else if (rolledDeck != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    rolledDeck.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
