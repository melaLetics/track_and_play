import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/month_names.dart';
import '../../../../database/app_database.dart';
import '../../controller/provider/games_repository_provider.dart';
import '../../model/game_mode_labels.dart';
import 'game_detail_screen.dart';
import 'game_setup_screen.dart';

/// Historie aller erfassten Partien (manuell nachgetragen oder live
/// gespielt), gruppiert nach Jahr und Monat (Nutzerwunsch, angelehnt
/// an mtg_stats_tracker - dort GameYearSection). Jahre stehen
/// neueste zuerst und sind initial aufgeklappt, Monate darunter
/// zunaechst eingeklappt (wie im Vorbild) - innerhalb eines Monats
/// bleibt die von der Datenbank gelieferte Reihenfolge (neueste
/// zuerst) erhalten.
///
/// Such-Symbol blendet ein Suchfeld + Modus-Filter ein (Nutzerwunsch:
/// "nach Spieler, Commander oder Deck suchen" und "nach Modus
/// filtern"). Die Suche laeuft rein lokal ueber die von
/// [gamesWithSearchTermsProvider] mitgelieferten Begriffe (siehe
/// GameListItem/GamesRepository.watchGamesWithSearchTerms) - kein
/// separater Riverpod-Filter-State noetig, analog zur Deck-Suche in
/// PlayerDetailScreen.
class GamesOverviewScreen extends ConsumerStatefulWidget {
  const GamesOverviewScreen({super.key});

  @override
  ConsumerState<GamesOverviewScreen> createState() =>
      _GamesOverviewScreenState();
}

class _GamesOverviewScreenState extends ConsumerState<GamesOverviewScreen> {
  bool _showFilter = false;
  String _searchQuery = '';
  GameMode? _selectedMode;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamesAsync = ref.watch(gamesWithSearchTermsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partien'),
        actions: [
          IconButton(
            icon: Icon(_showFilter ? Icons.search_off : Icons.search),
            tooltip: _showFilter ? 'Suche schließen' : 'Partien durchsuchen',
            onPressed: () => setState(() {
              _showFilter = !_showFilter;
              if (!_showFilter) {
                _searchController.clear();
                _searchQuery = '';
                _selectedMode = null;
              }
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Spieler, Commander oder Deck suchen',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<GameMode?>(
                    initialValue: _selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Modus',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<GameMode?>(
                        value: null,
                        child: Text('Alle Modi'),
                      ),
                      for (final mode in GameMode.values)
                        DropdownMenuItem<GameMode?>(
                          value: mode,
                          child: Text(gameModeLabels[mode] ?? mode.name),
                        ),
                    ],
                    onChanged: (mode) => setState(() => _selectedMode = mode),
                  ),
                ],
              ),
            ),
          Expanded(
            child: gamesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Fehler: $error')),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Noch keine Partie erfasst.\n'
                        'Tippe unten rechts auf "+", um deine erste Partie '
                        'anzulegen.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final query = _searchQuery.trim().toLowerCase();
                final visibleItems = items.where((item) {
                  if (_selectedMode != null &&
                      item.game.mode != _selectedMode) {
                    return false;
                  }
                  if (query.isEmpty) return true;
                  return item.searchTerms.any(
                    (term) => term.toLowerCase().contains(query),
                  );
                }).toList();

                if (visibleItems.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Keine Partien gefunden.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final Map<int, Map<int, List<Game>>> grouped = {};
                for (final item in visibleItems) {
                  final game = item.game;
                  final year = game.playedAt.year;
                  final month = game.playedAt.month;
                  grouped.putIfAbsent(year, () => {});
                  grouped[year]!.putIfAbsent(month, () => []);
                  grouped[year]![month]!.add(game);
                }
                final sortedYears = grouped.keys.toList()
                  ..sort((a, b) => b.compareTo(a));

                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children: [
                    for (final year in sortedYears)
                      _GameYearSection(
                        year: year,
                        gamesByMonth: grouped[year]!,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'games_overview_fab',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const GameSetupScreen()),
          );
        },
        tooltip: 'Neue Partie',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Ein Jahr als aufklappbare Karte (initial offen), darunter je
/// enthaltener Monat wiederum eine aufklappbare Sektion (initial
/// geschlossen) mit den einzelnen Partien darin.
class _GameYearSection extends StatelessWidget {
  final int year;
  final Map<int, List<Game>> gamesByMonth;

  const _GameYearSection({required this.year, required this.gamesByMonth});

  @override
  Widget build(BuildContext context) {
    final months = gamesByMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    final totalGames = gamesByMonth.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          '$year ($totalGames ${totalGames == 1 ? 'Partie' : 'Partien'})',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        children: [
          for (final month in months)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: ExpansionTile(
                title: Text(
                  '${monthNameDe(month)} (${gamesByMonth[month]!.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                children: [
                  for (final game in gamesByMonth[month]!)
                    _GameListTile(game: game),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GameListTile extends StatelessWidget {
  final Game game;

  const _GameListTile({required this.game});

  @override
  Widget build(BuildContext context) {
    final inProgress = game.status == GameStatus.inProgress;
    return ListTile(
      leading: Icon(
        inProgress ? Icons.play_circle_outline : Icons.check_circle_outline,
        color: inProgress ? Colors.orange : Colors.green,
      ),
      title: Text(gameModeLabels[game.mode] ?? game.mode.name),
      subtitle: Text(
        '${game.playedAt.day.toString().padLeft(2, '0')}.'
        '${game.playedAt.month.toString().padLeft(2, '0')}.'
        '${game.playedAt.year}'
        '${inProgress ? ' · läuft noch' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GameDetailScreen(gameId: game.id),
          ),
        );
      },
    );
  }
}
