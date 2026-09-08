import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../players/controller/provider/players_repository_provider.dart';
import '../../../decks/controller/provider/decks_repository_provider.dart';
import '../../model/game_participant_draft.dart';

/// Mehrstufiger Dialog: erst einen bekannten Spieler auswählen, dann
/// (optional) eines seiner eigenen Decks - oder ein GELIEHENES Deck
/// eines anderen Spielers (Eintrag "Geliehenes Deck", siehe
/// ARCHITECTURE.md) - oder "kein Deck angeben".
Future<GameParticipantDraft?> showAddKnownParticipantDialog(
  BuildContext context, {
  required Set<int> excludePlayerIds,
}) {
  return showDialog<GameParticipantDraft>(
    context: context,
    builder: (_) => _AddKnownParticipantDialog(excludePlayerIds: excludePlayerIds),
  );
}

enum _Step { pickPlayer, ownDeck, pickLender, pickLenderDeck }

class _AddKnownParticipantDialog extends ConsumerStatefulWidget {
  final Set<int> excludePlayerIds;

  const _AddKnownParticipantDialog({required this.excludePlayerIds});

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
    final playersAsync = ref.watch(allActivePlayersProvider);
    return AlertDialog(
      title: const Text('Bekannten Spieler auswählen'),
      content: SizedBox(
        width: double.maxFinite,
        child: playersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Fehler: $error'),
          data: (players) {
            final candidates = players
                .where((p) => !widget.excludePlayerIds.contains(p.id))
                .toList();
            if (candidates.isEmpty) {
              return const Text(
                'Keine weiteren bekannten Spieler verfügbar.',
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
                    subtitle: Text(
                      deck.colorIdentity.isEmpty ? 'Farblos' : deck.colorIdentity,
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
                    subtitle: Text(
                      deck.colorIdentity.isEmpty
                          ? 'Farblos'
                          : deck.colorIdentity,
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
