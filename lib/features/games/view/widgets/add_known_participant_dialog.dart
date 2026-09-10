import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/mana_symbol.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import '../../../decks/controller/provider/decks_repository_provider.dart';
import '../../../groups/controller/provider/groups_repository_provider.dart';
import '../../model/game_participant_draft.dart';

/// Mehrstufiger Dialog: erst einen bekannten Spieler auswählen, dann
/// (optional) eines seiner eigenen Decks - oder ein GELIEHENES Deck
/// eines anderen Spielers (Eintrag "Geliehenes Deck", siehe
/// ARCHITECTURE.md) - oder "kein Deck angeben".
///
/// [groupId] (Nutzerwunsch): ist beim Aufruf aus GameSetupScreen eine
/// Gruppe verlinkt, werden auf der Spieler-Auswahl-Stufe ERSTMAL nur
/// deren Mitglieder vorgeschlagen statt aller bekannten Spieler - ein
/// Link "Alle Spieler anzeigen" erweitert die Liste bei Bedarf (z. B.
/// Gast ohne Gruppenmitgliedschaft). Die Deck-/Verleih-Auswahl danach
/// bleibt unverändert ungefiltert - eine Gruppe schränkt nur ein, WER
/// als Teilnehmer vorgeschlagen wird, nicht wessen Deck geliehen
/// werden kann.
Future<GameParticipantDraft?> showAddKnownParticipantDialog(
  BuildContext context, {
  required Set<int> excludePlayerIds,
  int? groupId,
}) {
  return showDialog<GameParticipantDraft>(
    context: context,
    builder: (_) => _AddKnownParticipantDialog(
      excludePlayerIds: excludePlayerIds,
      groupId: groupId,
    ),
  );
}

enum _Step { pickPlayer, ownDeck, pickLender, pickLenderDeck }

class _AddKnownParticipantDialog extends ConsumerStatefulWidget {
  final Set<int> excludePlayerIds;
  final int? groupId;

  const _AddKnownParticipantDialog({
    required this.excludePlayerIds,
    this.groupId,
  });

  @override
  ConsumerState<_AddKnownParticipantDialog> createState() =>
      _AddKnownParticipantDialogState();
}

class _AddKnownParticipantDialogState
    extends ConsumerState<_AddKnownParticipantDialog> {
  _Step _step = _Step.pickPlayer;
  int? _selectedPlayerId;
  String? _selectedPlayerName;
  int? _lenderId;
  String? _lenderName;

  /// Nur relevant, wenn widget.groupId gesetzt ist: true, sobald der
  /// Nutzer explizit "Alle Spieler anzeigen" angetippt hat - dann
  /// bleibt für den Rest dieser Dialog-Instanz die ungefilterte Liste
  /// aktiv (bewusst kein Zurück-Toggle, da sonst eine bereits
  /// getroffene Auswahl außerhalb der Gruppe wieder aus der Liste
  /// verschwinden könnte).
  bool _showAllPlayers = false;

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.pickPlayer:
        return _buildPickPlayerStep(context);
      case _Step.ownDeck:
        return _buildOwnDeckStep(context);
      case _Step.pickLender:
        return _buildPickLenderStep(context);
      case _Step.pickLenderDeck:
        return _buildPickLenderDeckStep(context);
    }
  }

  Widget _buildPickPlayerStep(BuildContext context) {
    final restrictToGroup = widget.groupId != null && !_showAllPlayers;
    final playersAsync = restrictToGroup
        ? ref.watch(groupMembersProvider(widget.groupId!))
        : ref.watch(allActivePlayersProvider);
    return AlertDialog(
      title: const Text('Bekannten Spieler auswählen'),
      content: SizedBox(
        width: double.maxFinite,
        child: playersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Fehler: $error'),
          data: (players) {
            // !p.archived zusätzlich nötig, weil groupMembersProvider
            // (anders als allActivePlayersProvider) archivierte
            // Mitglieder NICHT herausfiltert (siehe
            // GroupsRepository.watchMembers) - ohne diesen Filter
            // könnten bei gruppen-eingeschränkter Anzeige archivierte
            // Spieler vorgeschlagen werden, was vorher nie möglich war.
            final candidates = players
                .where(
                  (p) => !widget.excludePlayerIds.contains(p.id) && !p.archived,
                )
                .toList();
            final expandLink = restrictToGroup
                ? TextButton(
                    onPressed: () => setState(() => _showAllPlayers = true),
                    child: const Text('Alle Spieler anzeigen'),
                  )
                : null;
            if (candidates.isEmpty) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restrictToGroup
                        ? 'Keine weiteren Gruppenmitglieder verfügbar.'
                        : 'Keine weiteren bekannten Spieler verfügbar.',
                  ),
                  if (expandLink != null) expandLink,
                ],
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final player in candidates)
                  ListTile(
                    title: Text(player.name),
                    onTap: () => setState(() {
                      _selectedPlayerId = player.id;
                      _selectedPlayerName = player.name;
                      _step = _Step.ownDeck;
                    }),
                  ),
                if (expandLink != null) expandLink,
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }

  Widget _buildOwnDeckStep(BuildContext context) {
    final decksAsync = ref.watch(playerDecksProvider(_selectedPlayerId!));
    return AlertDialog(
      title: Text('Deck von $_selectedPlayerName'),
      content: SizedBox(
        width: double.maxFinite,
        child: decksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Fehler: $error'),
          data: (decks) {
            return ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: const Text('Kein Deck angeben'),
                  onTap: () => Navigator.of(context).pop(
                    GameParticipantDraft(
                      playerId: _selectedPlayerId,
                      playerName: _selectedPlayerName,
                    ),
                  ),
                ),
                for (final deck in decks)
                  ListTile(
                    title: Text(deck.name),
                    subtitle: _DeckSubtitle(
                      colorIdentity: deck.colorIdentity,
                      bracket: deck.bracket,
                    ),
                    onTap: () => Navigator.of(context).pop(
                      GameParticipantDraft(
                        playerId: _selectedPlayerId,
                        playerName: _selectedPlayerName,
                        deckId: deck.id,
                        deckName: deck.name,
                        colorIdentity: deck.colorIdentity,
                      ),
                    ),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('Geliehenes Deck'),
                  subtitle: const Text('von einem anderen Spieler'),
                  onTap: () => setState(() => _step = _Step.pickLender),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _selectedPlayerId = null;
            _selectedPlayerName = null;
            _step = _Step.pickPlayer;
          }),
          child: const Text('Zurück'),
        ),
      ],
    );
  }

  Widget _buildPickLenderStep(BuildContext context) {
    final playersAsync = ref.watch(allActivePlayersProvider);
    return AlertDialog(
      title: const Text('Deck von wem geliehen?'),
      content: SizedBox(
        width: double.maxFinite,
        child: playersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Fehler: $error'),
          data: (players) {
            final candidates =
                players.where((p) => p.id != _selectedPlayerId).toList();
            if (candidates.isEmpty) {
              return const Text('Kein anderer Spieler verfügbar.');
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final player in candidates)
                  ListTile(
                    title: Text(player.name),
                    onTap: () => setState(() {
                      _lenderId = player.id;
                      _lenderName = player.name;
                      _step = _Step.pickLenderDeck;
                    }),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _step = _Step.ownDeck),
          child: const Text('Zurück'),
        ),
      ],
    );
  }

  Widget _buildPickLenderDeckStep(BuildContext context) {
    final decksAsync = ref.watch(playerDecksProvider(_lenderId!));
    return AlertDialog(
      title: Text('Deck von $_lenderName'),
      content: SizedBox(
        width: double.maxFinite,
        child: decksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Fehler: $error'),
          data: (decks) {
            if (decks.isEmpty) {
              return Text('$_lenderName hat noch keine Decks angelegt.');
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final deck in decks)
                  ListTile(
                    title: Text(deck.name),
                    subtitle: _DeckSubtitle(
                      colorIdentity: deck.colorIdentity,
                      bracket: deck.bracket,
                    ),
                    onTap: () => Navigator.of(context).pop(
                      GameParticipantDraft(
                        playerId: _selectedPlayerId,
                        playerName: _selectedPlayerName,
                        deckId: deck.id,
                        deckName: deck.name,
                        colorIdentity: deck.colorIdentity,
                        deckOwnerPlayerId: _lenderId,
                        deckOwnerName: _lenderName,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _lenderId = null;
            _lenderName = null;
            _step = _Step.pickLender;
          }),
          child: const Text('Zurück'),
        ),
      ],
    );
  }
}

/// Subtitle-Zeile für einen Deck-Eintrag in den Deck-Auswahllisten
/// dieser Datei (Nutzerwunsch, "Kosmetik" bei der Mitspieler-Auswahl):
/// echte Mana-Symbole statt des rohen WUBRG-Buchstaben-Kürzels (siehe
/// ManaSymbolRow, core/widgets/mana_symbol.dart - bereits an anderer
/// Stelle im Statistik-Dashboard genutzt), zusätzlich das Bracket
/// (siehe Decks.bracket), aber NUR wenn eines gesetzt ist - anders
/// als die Farbidentität (die auch als "farblos" immer einen Wert
/// zeigt) bleibt das Bracket bei den meisten Decks unausgefüllt und
/// soll dann nicht als "Bracket null" o. ä. auftauchen.
class _DeckSubtitle extends StatelessWidget {
  final String colorIdentity;
  final int? bracket;

  const _DeckSubtitle({required this.colorIdentity, required this.bracket});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ManaSymbolRow(colorIdentity: colorIdentity),
        if (bracket != null) ...[
          const SizedBox(width: 8),
          Text('Bracket $bracket'),
        ],
      ],
    );
  }
}
