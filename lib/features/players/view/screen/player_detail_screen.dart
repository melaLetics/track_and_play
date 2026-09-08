import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/rename_dialog.dart';
import '../../controller/provider/players_repository_provider.dart';
import '../../../decks/controller/provider/decks_repository_provider.dart';
import '../../../decks/model/deck_build_type_labels.dart';
import '../../../decks/view/widgets/deck_form_dialog.dart';
import '../../../decks/view/widgets/deck_stack_card.dart';
import '../../../export/controller/provider/export_service_provider.dart';
import '../../../export/view/widgets/qr_share_dialog.dart';

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
/// vorliegt.
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
                if (visibleDecks.isEmpty) {
                  return const Center(
                    child: Text(
                      'Keine Decks gefunden.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: visibleDecks.length,
                  itemBuilder: (context, index) {
                    final deck = visibleDecks[index];
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
        onPressed: () => showDeckFormDialog(context, ownerPlayerId: playerId),
        tooltip: 'Neues Deck',
        child: const Icon(Icons.add),
      ),
    );
  }
}
