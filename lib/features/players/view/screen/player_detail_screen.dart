import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/rename_dialog.dart';
import '../../../../database/app_database.dart';
import '../../controller/provider/players_repository_provider.dart';
import '../../../decks/controller/provider/decks_repository_provider.dart';
import '../../../decks/model/deck_build_type_labels.dart';
import '../../../decks/view/widgets/deck_form_dialog.dart';
import '../../../decks/view/widgets/deck_stack_card.dart';
import '../../../export/controller/provider/export_service_provider.dart';
import '../../../export/view/widgets/qr_share_dialog.dart';
import '../../../games/controller/provider/games_repository_provider.dart';
import '../../../stats/model/player_stats.dart';

/// Sortierkriterium für die Deck-Liste in [PlayerDetailScreen]
/// (Nutzerwunsch: "Decks nach ihrer Performance sortieren können").
/// [name] ist die bisherige (implizite) Standard-Sortierung, die
/// übrigen drei nutzen dieselbe Performance-Aggregation wie das
/// Statistik-Dashboard (siehe GamesRepository.watchSelfGameStats/
/// computePlayerStats - trotz des Namens "self" bereits für einen
/// BELIEBIGEN Spieler parametrisiert, hier also für den gerade
/// angezeigten Spieler statt zwingend den Ich-Spieler). "Performance"
/// bezieht sich dabei auf Partien, in denen der PLAYER DIESES SCREENS
/// das jeweilige Deck selbst gespielt hat (nicht auf Partien, in denen
/// es an jemand anderen verliehen war - siehe DeckWinStats.isOwnDeck/
/// Deck-Verleih in ARCHITECTURE.md).
enum _DeckSort { name, winRate, wins, gamesPlayed }

const Map<_DeckSort, String> _deckSortLabels = {
  _DeckSort.name: 'Name (A-Z)',
  _DeckSort.winRate: 'Winrate',
  _DeckSort.wins: 'Siege',
  _DeckSort.gamesPlayed: 'Anzahl Partien',
};

/// Zeigt einen Spieler (sich selbst oder ein Gruppenmitglied) und seine
/// Decks. Von hier aus werden Decks angelegt/bearbeitet/archiviert und
/// der Spieler kann umbenannt bzw. (außer sich selbst) archiviert/
/// reaktiviert werden. Der "Archivierte anzeigen"-Umschalter (siehe
/// ARCHITECTURE.md, Nutzeranforderung "Wie sehe ich archivierte
/// Daten?") blendet zusätzlich archivierte Decks ein, sonst waren
/// diese nach dem Archivieren nirgends mehr sichtbar/reaktivierbar.
/// Das Such-Symbol blendet ein Suchfeld ein, das die (bereits per
/// [_showArchivedDecks] geladene) Deck-Liste rein lokal nach
/// Deck-Name UND Commander-Name filtert (Nutzerwunsch) - kein neuer
/// Provider noetig, da die Liste hier ohnehin schon vollstaendig
/// vorliegt. Das Sortier-Symbol (siehe [_DeckSort], Nutzerwunsch)
/// erlaubt zusätzlich zur alphabetischen Sortierung eine nach
/// Performance (Winrate/Siege/Partien).
class PlayerDetailScreen extends ConsumerStatefulWidget {
  final int playerId;

  const PlayerDetailScreen({super.key, required this.playerId});

  @override
  ConsumerState<PlayerDetailScreen> createState() =>
      _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends ConsumerState<PlayerDetailScreen> {
  bool _showArchivedDecks = false;
  bool _showSearch = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  _DeckSort _sortBy = _DeckSort.name;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerId = widget.playerId;
    final playerAsync = ref.watch(playerByIdProvider(playerId));
    final decksAsync = ref.watch(
      _showArchivedDecks
          ? allPlayerDecksProvider(playerId)
          : playerDecksProvider(playerId),
    );
    // Für die Performance-Sortierung/-Anzeige (siehe _DeckSort) - bewusst
    // tolerant per maybeWhen: solange diese (schnelle, rein lokale)
    // Statistik noch lädt oder fehlschlägt, wird einfach mit einer
    // leeren Map weitergemacht (alle Decks gelten dann als "0 Partien"
    // statt die komplette Deck-Liste hinter einem zweiten Ladespinner
    // zu verstecken).
    final statsAsync = ref.watch(selfGameStatsProvider(playerId));
    final statsByDeckId = statsAsync.maybeWhen(
      data: (rows) => {
        for (final d in computePlayerStats(rows).byDeck)
          if (d.deckId != null) d.deckId!: d,
      },
      orElse: () => const <int, DeckWinStats>{},
    );

    return Scaffold(
      appBar: AppBar(
        title: playerAsync.when(
          loading: () => const Text('...'),
          error: (_, __) => const Text('Spieler'),
          data: (player) => Text(player?.name ?? 'Spieler'),
        ),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: _showSearch ? 'Suche schließen' : 'Decks durchsuchen',
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                _searchQuery = '';
              }
            }),
          ),
          IconButton(
            icon: Icon(
              _showArchivedDecks
                  ? Icons.archive
                  : Icons.archive_outlined,
            ),
            tooltip: _showArchivedDecks
                ? 'Archivierte Decks ausblenden'
                : 'Archivierte Decks anzeigen',
            onPressed: () =>
                setState(() => _showArchivedDecks = !_showArchivedDecks),
          ),
          PopupMenuButton<_DeckSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Decks sortieren',
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => [
              for (final sort in _DeckSort.values)
                PopupMenuItem(
                  value: sort,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(sort == _sortBy ? Icons.check : null, size: 16),
                      const SizedBox(width: 8),
                      Text(_deckSortLabels[sort]!),
                    ],
                  ),
                ),
            ],
          ),
          playerAsync.maybeWhen(
            data: (player) {
              if (player == null) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'share_player') {
                    final bundle = await ref
                        .read(exportServiceProvider)
                        .buildPlayerQrBundle(playerId);
                    if (!context.mounted) return;
                    showQrShareDialog(
                      context,
                      title: 'Spieler teilen: ${player.name}',
                      bundle: bundle,
                    );
                  } else if (value == 'rename') {
                    showRenameDialog(
                      context,
                      title: 'Spieler umbenennen',
                      currentName: player.name,
                      label: 'Name',
                      // Muss zur Players.name-Spaltenbegrenzung passen
                      // (siehe players_table.dart, withLength(max: 60)).
                      maxLength: 60,
                      onSave: (name) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(playersRepositoryProvider)
                              .renamePlayer(playerId, name);
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Fehler beim Speichern: $e')),
                          );
                        }
                      },
                    );
                  } else if (value == 'archive') {
                    // Umschalter statt Einbahnstraße - siehe
                    // deck_form_dialog.dart für dieselbe Ergänzung bei
                    // Decks.
                    final archiveNow = !player.archived;
                    await ref
                        .read(playersRepositoryProvider)
                        .setArchived(playerId, archiveNow);
                    if (!context.mounted) return;
                    if (archiveNow) Navigator.of(context).pop();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'share_player',
                    child: Text('Spieler teilen (QR)'),
                  ),
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Umbenennen'),
                  ),
                  if (!player.isSelf)
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(
                        player.archived ? 'Reaktivieren' : 'Archivieren',
                      ),
                    ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Deck oder Commander suchen',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          Expanded(
            child: decksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Fehler: $error')),
              data: (decks) {
                if (decks.isEmpty) {
                  return Center(
                    child: Text(
                      _showArchivedDecks
                          ? 'Noch keine Decks angelegt.'
                          : 'Noch keine Decks angelegt.\n'
                              '(Über das Archiv-Symbol oben lassen sich auch '
                              'archivierte Decks einblenden.)',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final query = _searchQuery.trim().toLowerCase();
                final visibleDecks = query.isEmpty
                    ? decks
                    : decks.where((deck) {
                        final nameMatch =
                            deck.name.toLowerCase().contains(query);
                        final commanderMatch =
                            (deck.commanderName ?? '')
                                .toLowerCase()
                                .contains(query);
                        final commander2Match =
                            (deck.secondCommanderName ?? '')
                                .toLowerCase()
                                .contains(query);
                        return nameMatch || commanderMatch || commander2Match;
                      }).toList();
                final sortedDecks =
                    _sortDecks(visibleDecks, _sortBy, statsByDeckId);
                if (sortedDecks.isEmpty) {
                  return const Center(
                    child: Text(
                      'Keine Decks gefunden.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: sortedDecks.length,
                  itemBuilder: (context, index) {
                    final deck = sortedDecks[index];
              final commanderLine = deck.commanderName != null &&
                      deck.commanderName!.isNotEmpty
                  ? [
                      deck.commanderName!,
                      if (deck.secondCommanderName != null &&
                          deck.secondCommanderName!.isNotEmpty)
                        deck.secondCommanderName!,
                    ].join(' / ')
                  : null;
              final subtitleParts = [
                // Performance-Kennzahl vorangestellt, aber nur wenn
                // auch danach sortiert wird - bei "Name" bleibt die
                // Zeile wie zuvor (Nutzerwunsch war Sortierung, keine
                // dauerhafte Zusatzanzeige).
                if (_sortBy != _DeckSort.name)
                  _performanceLabel(_sortBy, statsByDeckId[deck.id]),
                commanderLine ??
                    (deck.colorIdentity.isEmpty
                        ? 'Farblos'
                        : deck.colorIdentity),
                if (deck.bracket != null) 'Bracket ${deck.bracket}',
                if (deck.buildType != null)
                  deckBuildTypeLabels[deck.buildType!] ?? deck.buildType!.name,
                if (deck.archived) 'archiviert',
              ];
              return DeckStackCard(
                name: deck.name,
                subtitle: subtitleParts.join(' · '),
                link: deck.deckLink,
                colorIdentity: deck.colorIdentity,
                archived: deck.archived,
                trailing: IconButton(
                  icon: const Icon(Icons.qr_code),
                  tooltip: 'Deck teilen (QR)',
                  onPressed: () async {
                    final bundle = await ref
                        .read(exportServiceProvider)
                        .buildDeckQrBundle(deck.id);
                    if (!context.mounted) return;
                    showQrShareDialog(
                      context,
                      title: 'Deck teilen: ${deck.name}',
                      bundle: bundle,
                    );
                  },
                ),
                onTap: () => showDeckFormDialog(
                  context,
                  ownerPlayerId: playerId,
                  existingDeck: deck,
                ),
              );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'player_detail_fab',
        onPressed: () => showDeckFormDialog(context, ownerPlayerId: playerId),
        tooltip: 'Neues Deck',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Sortiert [decks] nach [sortBy] (siehe [_DeckSort]). Bei den drei
/// Performance-Kriterien wird absteigend sortiert (bestes Deck zuerst)
/// mit dem Deck-Namen als Tiebreaker bei Gleichstand (v. a. relevant
/// für Decks ohne jede Partie, die sonst in beliebiger Reihenfolge
/// nebeneinander landen wuerden) - Decks ohne Eintrag in
/// [statsByDeckId] (noch nie vom Besitzer dieses Screens selbst
/// gespielt) gelten dabei als 0 und rutschen so automatisch ans Ende.
List<Deck> _sortDecks(
  List<Deck> decks,
  _DeckSort sortBy,
  Map<int, DeckWinStats> statsByDeckId,
) {
  final sorted = [...decks];
  int byNameAsc(Deck a, Deck b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  switch (sortBy) {
    case _DeckSort.name:
      sorted.sort(byNameAsc);
      break;
    case _DeckSort.winRate:
      sorted.sort((a, b) {
        final ra = statsByDeckId[a.id]?.winRate;
        final rb = statsByDeckId[b.id]?.winRate;
        if (ra == null && rb == null) return byNameAsc(a, b);
        if (ra == null) return 1;
        if (rb == null) return -1;
        final cmp = rb.compareTo(ra);
        return cmp != 0 ? cmp : byNameAsc(a, b);
      });
      break;
    case _DeckSort.wins:
      sorted.sort((a, b) {
        final wa = statsByDeckId[a.id]?.wins ?? 0;
        final wb = statsByDeckId[b.id]?.wins ?? 0;
        final cmp = wb.compareTo(wa);
        return cmp != 0 ? cmp : byNameAsc(a, b);
      });
      break;
    case _DeckSort.gamesPlayed:
      sorted.sort((a, b) {
        final ga = statsByDeckId[a.id]?.gamesPlayed ?? 0;
        final gb = statsByDeckId[b.id]?.gamesPlayed ?? 0;
        final cmp = gb.compareTo(ga);
        return cmp != 0 ? cmp : byNameAsc(a, b);
      });
      break;
  }
  return sorted;
}

/// Kurzer Anzeige-Text der zum aktuellen [_DeckSort] passenden
/// Kennzahl, der Deck-Karte vorangestellt (siehe Aufrufstelle) -
/// macht die gewählte Sortierung nachvollziehbar. [stats] ist null,
/// wenn der Besitzer dieses Screens das Deck noch nie selbst gespielt
/// hat (siehe [_sortDecks]).
String _performanceLabel(_DeckSort sortBy, DeckWinStats? stats) {
  switch (sortBy) {
    case _DeckSort.winRate:
      if (stats == null || stats.winRate == null) return 'Noch keine Partien';
      return '${(stats.winRate! * 100).round()}% Siege '
          '(${stats.wins}/${stats.gamesPlayed})';
    case _DeckSort.wins:
      return '${stats?.wins ?? 0} Siege';
    case _DeckSort.gamesPlayed:
      return '${stats?.gamesPlayed ?? 0} Partien';
    case _DeckSort.name:
      return '';
  }
}
