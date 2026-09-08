import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../decks/controller/provider/decks_repository_provider.dart';
import '../../../export/model/export_bundle.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import '../../model/import_preview.dart';
import '../../model/participant_override.dart';

/// Eine Partie in der Import-Vorschau (siehe ImportWizardScreen):
/// Checkbox zum Ein-/Ausschließen wie bei den anderen Kategorien, plus
/// aufklappbare Teilnehmer-Zuordnung - für jeden Teilnehmer lässt sich
/// "on the fly" festlegen, dass er einem bereits bekannten lokalen
/// Spieler entspricht (z. B. dem Ich-Spieler) und welches EIGENE Deck
/// er dabei gespielt hat (z. B. statt nur der erfassten Farbidentität
/// "WU" ein konkretes eigenes WU-Deck) - unabhängig vom im Bundle
/// erfassten Namen. Ohne Übersteuerung greift wie gehabt der
/// automatische Namens-Abgleich (siehe ImportService).
class GameImportTile extends ConsumerStatefulWidget {
  final int gameIndex;
  final GameExport game;
  final ImportPreviewEntry entry;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final Map<int, ParticipantOverride> overrides;
  final void Function(int participantIndex, ParticipantOverride override)
      onOverrideChanged;

  const GameImportTile({
    super.key,
    required this.gameIndex,
    required this.game,
    required this.entry,
    required this.selected,
    required this.onSelectedChanged,
    required this.overrides,
    required this.onOverrideChanged,
  });

  @override
  ConsumerState<GameImportTile> createState() => _GameImportTileState();
}

class _GameImportTileState extends ConsumerState<GameImportTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(widget.entry.title),
            subtitle:
                widget.entry.subtitle != null ? Text(widget.entry.subtitle!) : null,
            value: widget.selected,
            onChanged: (v) => widget.onSelectedChanged(v ?? false),
            secondary: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              tooltip: 'Teilnehmer zuordnen',
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const Text(
                    'Wer war das wirklich - und mit welchem eigenen Deck?',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < widget.game.participants.length; i++)
                    _ParticipantRow(
                      participant: widget.game.participants[i],
                      participantOverride:
                          widget.overrides[i] ?? const ParticipantOverride.auto(),
                      onChanged: (o) => widget.onOverrideChanged(i, o),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends ConsumerWidget {
  final GameParticipantExport participant;
  final ParticipantOverride participantOverride;
  final ValueChanged<ParticipantOverride> onChanged;

  const _ParticipantRow({
    required this.participant,
    required this.participantOverride,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfAsync = ref.watch(selfPlayerProvider);
    final playersAsync = ref.watch(allActivePlayersProvider);

    final label =
        participant.playerName ?? participant.anonymousLabel ?? 'Unbekannt';
    final colorLabel =
        participant.colorIdentity.isEmpty ? 'farblos' : participant.colorIdentity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ($colorLabel)', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          selfAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (self) => playersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (players) {
                final items = <DropdownMenuItem<String>>[
                  const DropdownMenuItem(
                    value: 'auto',
                    child: Text('Automatisch (Namens-Abgleich)'),
                  ),
                  if (self != null)
                    DropdownMenuItem(
                      value: 'p${self.id}',
                      child: Text('Ich (${self.name})'),
                    ),
                  for (final p in players)
                    if (p.id != self?.id)
                      DropdownMenuItem(value: 'p${p.id}', child: Text(p.name)),
                  const DropdownMenuItem(
                    value: 'anon',
                    child: Text('Anonym bleiben'),
                  ),
                ];
                final currentValue = switch (participantOverride.mode) {
                  ParticipantOverrideMode.auto => 'auto',
                  ParticipantOverrideMode.anonymous => 'anon',
                  ParticipantOverrideMode.assign =>
                    'p${participantOverride.playerId}',
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButton<String>(
                      isExpanded: true,
                      value: currentValue,
                      items: items,
                      onChanged: (value) {
                        if (value == null || value == 'auto') {
                          onChanged(const ParticipantOverride.auto());
                        } else if (value == 'anon') {
                          onChanged(const ParticipantOverride.anonymous());
                        } else {
                          final playerId = int.parse(value.substring(1));
                          onChanged(ParticipantOverride.assign(playerId: playerId));
                        }
                      },
                    ),
                    if (participantOverride.mode ==
                        ParticipantOverrideMode.assign)
                      _DeckPicker(
                        playerId: participantOverride.playerId!,
                        preferredColorIdentity: participant.colorIdentity,
                        selectedDeckId: participantOverride.deckId,
                        onChanged: (deckId) => onChanged(
                          ParticipantOverride.assign(
                            playerId: participantOverride.playerId!,
                            deckId: deckId,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Deck-Auswahl für den in [_ParticipantRow] zugeordneten Spieler.
/// Gibt es genau EIN eigenes Deck mit exakt passender Farbidentität
/// ([preferredColorIdentity]), wird es einmalig als Empfehlung
/// vorausgewählt (danach frei änderbar) - genau der vom Nutzer
/// gewünschte "ich habe statt WU genau dieses (WU) Deck gespielt"-Fall.
class _DeckPicker extends ConsumerWidget {
  final int playerId;
  final String preferredColorIdentity;
  final int? selectedDeckId;
  final ValueChanged<int?> onChanged;

  const _DeckPicker({
    required this.playerId,
    required this.preferredColorIdentity,
    required this.selectedDeckId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decksAsync = ref.watch(playerDecksProvider(playerId));
    return decksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (decks) {
        var effectiveSelection = selectedDeckId;
        if (effectiveSelection == null && preferredColorIdentity.isNotEmpty) {
          final matches =
              decks.where((d) => d.colorIdentity == preferredColorIdentity).toList();
          if (matches.length == 1) {
            effectiveSelection = matches.single.id;
            final matchedId = effectiveSelection;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onChanged(matchedId);
            });
          }
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: DropdownButton<int?>(
            isExpanded: true,
            value: effectiveSelection,
            hint: const Text('Deck wählen'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Kein Deck angeben'),
              ),
              for (final d in decks)
                DropdownMenuItem<int?>(
                  value: d.id,
                  child: Text(
                    '${d.name} (${d.colorIdentity.isEmpty ? 'farblos' : d.colorIdentity})',
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}
