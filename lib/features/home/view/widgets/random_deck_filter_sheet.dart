import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/provider/random_deck_filter_provider.dart';
import '../../model/random_deck_filter_state.dart';

/// Filter-Bottom-Sheet der Random-Deck-Funktion (Bracket/Art des
/// Decks/Proxy) - 1:1 aus mtg_stats_tracker übernommen
/// (RandomDeckFilterBottomSheet), nur die Provider-Namen angepasst.
class RandomDeckFilterSheet extends ConsumerWidget {
  const RandomDeckFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(randomDeckFilterProvider);
    final notifier = ref.read(randomDeckFilterProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filter', style: Theme.of(context).textTheme.headlineSmall),
                TextButton(
                  onPressed: filter.hasActiveFilters ? notifier.reset : null,
                  child: Text(
                    'Zurücksetzen',
                    style: TextStyle(
                      color: filter.hasActiveFilters
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Bracket'),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              multiSelectionEnabled: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {filter.bracket},
              onSelectionChanged: (selection) {
                notifier.setBracket(selection.first);
              },
            ),
            const SizedBox(height: 16),
            const Text('Art des Decks'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Precon'),
                  selected: filter.type == TypeFilter.precon,
                  onSelected: (selected) {
                    notifier.setTypeFilter(
                      selected ? TypeFilter.precon : TypeFilter.all,
                    );
                  },
                ),
                FilterChip(
                  label: const Text('Precon (aufgewertet)'),
                  selected: filter.type == TypeFilter.upgraded,
                  onSelected: (selected) {
                    notifier.setTypeFilter(
                      selected ? TypeFilter.upgraded : TypeFilter.all,
                    );
                  },
                ),
                FilterChip(
                  label: const Text('Eigenbau'),
                  selected: filter.type == TypeFilter.homebrew,
                  onSelected: (selected) {
                    notifier.setTypeFilter(
                      selected ? TypeFilter.homebrew : TypeFilter.all,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Enthält Proxies'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  showCheckmark: false,
                  avatar: const Icon(Icons.check),
                  label: const Text('Proxy'),
                  selected: filter.proxy == ProxyFilter.proxyOnly,
                  onSelected: (selected) {
                    notifier.setProxyFilter(
                      selected ? ProxyFilter.proxyOnly : ProxyFilter.all,
                    );
                  },
                ),
                FilterChip(
                  showCheckmark: false,
                  avatar: const Icon(Icons.close),
                  label: const Text('Nur Originalkarten'),
                  selected: filter.proxy == ProxyFilter.originalOnly,
                  onSelected: (selected) {
                    notifier.setProxyFilter(
                      selected ? ProxyFilter.originalOnly : ProxyFilter.all,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
