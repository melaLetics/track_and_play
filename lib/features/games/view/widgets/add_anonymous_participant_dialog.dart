import 'package:flutter/material.dart';

import '../../../decks/view/widgets/color_identity_picker.dart';
import '../../model/game_participant_draft.dart';

/// Dialog zum Hinzufuegen eines anonymen Teilnehmers zu einer Partie.
/// Es wird nur eine optionale Bezeichnung (z. B. "Gast von Chris") und die
/// Farbidentitaet des gespielten Decks erfasst - kein Spieler- oder
/// Deck-Datensatz. Solche Teilnehmer bleiben dauerhaft anonym.
Future<GameParticipantDraft?> showAddAnonymousParticipantDialog(
  BuildContext context,
) {
  return showDialog<GameParticipantDraft>(
    context: context,
    builder: (context) => const _AddAnonymousParticipantDialog(),
  );
}

class _AddAnonymousParticipantDialog extends StatefulWidget {
  const _AddAnonymousParticipantDialog();

  @override
  State<_AddAnonymousParticipantDialog> createState() =>
      _AddAnonymousParticipantDialogState();
}

class _AddAnonymousParticipantDialogState
    extends State<_AddAnonymousParticipantDialog> {
  final _labelController = TextEditingController();
  String _colorIdentity = '';

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unbekannten Spieler hinzufuegen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung (optional, z. B. Gast von Chris)',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Farbidentitaet des Decks'),
            const SizedBox(height: 8),
            ColorIdentityPicker(
              colorIdentity: _colorIdentity,
              onChanged: (value) => setState(() => _colorIdentity = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final label = _labelController.text.trim();
            Navigator.of(context).pop(
              GameParticipantDraft(
                anonymousLabel: label.isEmpty ? null : label,
                colorIdentity: _colorIdentity,
              ),
            );
          },
          child: const Text('Hinzufuegen'),
        ),
      ],
    );
  }
}
