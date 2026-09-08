import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../decks/controller/provider/decks_repository_provider.dart';
import '../../../players/controller/provider/players_repository_provider.dart';

/// Ergebnis einer Deck-Auswahl in [showSelectDeckDialog]. `deckId ==
/// null` bedeutet die bewusste Wahl "Kein Deck angeben" - ein
/// abgebrochener Dialog liefert stattdessen `null` statt eines
/// [DeckSelection]-Objekts zurück, die beiden Fälle sind also
/// unterscheidbar.
///
/// [ownerPlayerId]/[ownerName] sind nur bei einem GELIEHENEN Deck
/// gesetzt (Eintrag "Geliehenes Deck", siehe unten) - bei einem
/// eigenen Deck oder "Kein Deck angeben" bleiben sie null.
class DeckSelection {
  final int? deckId;
  final String? deckName;
  final String colorIdentity;
  final int? ownerPlayerId;
  final String? ownerName;

  const DeckSelection({
    this.deckId,
    this.deckName,
    this.colorIdentity = '',
    this.ownerPlayerId,
    this.ownerName,
  });
}

/// Zeigt die Deck-Liste eines bereits bekannten Spielers zur Auswahl an
/// (inkl. "Kein Deck angeben" und "Geliehenes Deck" für ein Deck eines
/// ANDEREN Spielers - siehe ARCHITECTURE.md, mit dem Nutzer abgestimmte
/// Deck-Verleih-Funktion). Wird beim nachträglichen Ändern des Decks
/// eines schon zur Partie hinzugefügten Teilnehmers verwendet (siehe
/// game_setup_screen.dart) - der zweite Auswahlschritt in
/// add_known_participant_dialog.dart bleibt bewusst eigenständig
/// (dortige "Zurück"-Navigation zur Spielerauswahl passt nicht zu
/// diesem einstufigen Dialog hier).
Future<DeckSelection?> showSelectDeckDialog(
  BuildContext context, {
  required int playerId,
  required String playerName,
}) {
  return showDialog<DeckSelection>(
    context: context,
    builder: (_) =>
        _SelectDeckDialog(playerId: playerId, playerName: playerName),
  );
}

enum _Step { ownDeck, pickLender, pickLenderDeck }

class _SelectDeckDialog extends ConsumerStatefulWidget {
  final int playerId;
  final String playerName;

  const _SelectDeckDialog({required this.playerId, required this.playerName});

  @override
  ConsumerState<_SelectDeckDialog> createState() => _SelectDeckDialogState();
}

class _SelectDeckDialogState extends ConsumerState<_SelectDeckDialog> {
  _Step _step = _Step.ownDeck;
  int? _lenderId;
  String? _lenderName;

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.ownDeck:
        return _buildOwnDeckStep(context);
      case _Step.pickLender:
        return _buildPickLenderStep(context);
      case _Step.pickLenderDeck:
        return _buildPickLenderDeckStep(context);
    }
  }

  Widget _buildOwnDeckStep(BuildContext context) {
    final decksAsync = ref.watch(playerDecksProvider(widget.playerId));
    return AlertDialog(
      title: Text('Deck von ${widget.playerName}'),
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
                  onTap: () =>
                      Navigator.of(context).pop(const DeckSelection()),
                ),
                for (final deck in decks)
                  ListTile(
                    title: Text(deck.name),
                    subtitle: Text(
                      deck.colorIdentity.isEmpty
                          ? 'Farblos'
                          : deck.colorIdentity,
                    ),
                    onTap: () => Navigator.of(context).pop(
                      DeckSelection(
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
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
                players.where((p) => p.id != widget.playerId).toList();
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
                      DeckSelection(
                        deckId: deck.id,
                        deckName: deck.name,
                        colorIdentity: deck.colorIdentity,
                        ownerPlayerId: _lenderId,
                        ownerName: _lenderName,
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
