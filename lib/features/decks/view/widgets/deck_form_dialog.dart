import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../controller/provider/decks_repository_provider.dart';
import '../../model/deck_build_type_labels.dart';
import 'color_identity_picker.dart';

/// Öffnet den Dialog zum Anlegen (kein [existingDeck]) oder Bearbeiten/
/// Archivieren-Reaktivieren ([existingDeck] gesetzt) eines Decks.
Future<void> showDeckFormDialog(
  BuildContext context, {
  required int ownerPlayerId,
  Deck? existingDeck,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DeckFormDialog(
      ownerPlayerId: ownerPlayerId,
      existingDeck: existingDeck,
    ),
  );
}

class _DeckFormDialog extends ConsumerStatefulWidget {
  final int ownerPlayerId;
  final Deck? existingDeck;

  const _DeckFormDialog({required this.ownerPlayerId, this.existingDeck});

  @override
  ConsumerState<_DeckFormDialog> createState() => _DeckFormDialogState();
}

class _DeckFormDialogState extends ConsumerState<_DeckFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _commanderController;
  late final TextEditingController _commander2Controller;
  late final TextEditingController _deckLinkController;
  late String _colorIdentity;
  late bool _showSecondCommander;
  DeckBuildType? _buildType;
  int? _bracket;
  late bool _isProxy;
  late bool _isTournamentLegal;

  @override
  void initState() {
    super.initState();
    final deck = widget.existingDeck;
    _nameController = TextEditingController(text: deck?.name ?? '');
    _commanderController =
        TextEditingController(text: deck?.commanderName ?? '');
    _commander2Controller =
        TextEditingController(text: deck?.secondCommanderName ?? '');
    _deckLinkController = TextEditingController(text: deck?.deckLink ?? '');
    _colorIdentity = deck?.colorIdentity ?? '';
    _showSecondCommander = (deck?.secondCommanderName ?? '').isNotEmpty;
    _buildType = deck?.buildType;
    _bracket = deck?.bracket;
    _isProxy = deck?.isProxy ?? false;
    _isTournamentLegal = deck?.isTournamentLegal ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commanderController.dispose();
    _commander2Controller.dispose();
    _deckLinkController.dispose();
    super.dispose();
  }

  // Dialog sofort schliessen, danach erst speichern (statt erst zu
  // speichern und danach zu poppen): der DB-Schreibvorgang löst über
  // playerDecksProvider live einen Rebuild von PlayerDetailScreen aus,
  // der mit dem Pop der Dialog-Route kollidieren und eine
  // "_dependents.isEmpty"-Assertion auslösen kann, obwohl das Deck
  // korrekt gespeichert wird (rein optisches Problem, siehe auch
  // core/widgets/rename_dialog.dart für die ausführliche Begründung).
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final commander = _commanderController.text.trim();
    final commander2 = _commander2Controller.text.trim();
    final deckLink = _deckLinkController.text.trim();
    final repo = ref.read(decksRepositoryProvider);
    final ownerPlayerId = widget.ownerPlayerId;
    final existingDeck = widget.existingDeck;
    final colorIdentity = _colorIdentity;
    final buildType = _buildType;
    final bracket = _bracket;
    final isProxy = _isProxy;
    final isTournamentLegal = _isTournamentLegal;
    final messenger = ScaffoldMessenger.of(context);

    Navigator.of(context).pop();

    try {
      if (existingDeck == null) {
        await repo.createDeck(
          ownerPlayerId: ownerPlayerId,
          name: name,
          colorIdentity: colorIdentity,
          commanderName: commander.isEmpty ? null : commander,
          secondCommanderName: commander2.isEmpty ? null : commander2,
          buildType: buildType,
          bracket: bracket,
          isProxy: isProxy,
          isTournamentLegal: isTournamentLegal,
          deckLink: deckLink.isEmpty ? null : deckLink,
        );
      } else {
        await repo.updateDeck(
          existingDeck.id,
          name: name,
          colorIdentity: colorIdentity,
          commanderName: commander.isEmpty ? null : commander,
          secondCommanderName: commander2.isEmpty ? null : commander2,
          buildType: buildType,
          bracket: bracket,
          isProxy: isProxy,
          isTournamentLegal: isTournamentLegal,
          deckLink: deckLink.isEmpty ? null : deckLink,
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingDeck != null;

    return AlertDialog(
      title: Text(isEditing ? 'Deck bearbeiten' : 'Neues Deck'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              // Muss zur Decks.name-Spaltenbegrenzung passen (siehe
              // decks_table.dart, withLength(min: 1, max: 80)).
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Deckname'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commanderController,
              decoration: const InputDecoration(
                labelText: 'Commander (optional)',
              ),
            ),
            if (_showSecondCommander) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _commander2Controller,
                decoration: const InputDecoration(
                  labelText: 'Partner-Commander (optional)',
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _showSecondCommander = !_showSecondCommander;
                  if (!_showSecondCommander) _commander2Controller.clear();
                }),
                icon: Icon(_showSecondCommander ? Icons.remove : Icons.add),
                label: Text(
                  _showSecondCommander
                      ? 'Partner-Commander entfernen'
                      : 'Partner-Commander hinzufügen',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Farbidentität'),
            ),
            const SizedBox(height: 8),
            ColorIdentityPicker(
              colorIdentity: _colorIdentity,
              onChanged: (updated) => setState(() => _colorIdentity = updated),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<DeckBuildType?>(
              initialValue: _buildType,
              decoration: const InputDecoration(labelText: 'Bauart (optional)'),
              items: [
                const DropdownMenuItem<DeckBuildType?>(
                  value: null,
                  child: Text('Keine Angabe'),
                ),
                for (final type in DeckBuildType.values)
                  DropdownMenuItem<DeckBuildType?>(
                    value: type,
                    child: Text(deckBuildTypeLabels[type] ?? type.name),
                  ),
              ],
              onChanged: (value) => setState(() => _buildType = value),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Bracket (optional):'),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _bracket == null
                      ? null
                      : () => setState(() {
                            final next = _bracket! - 1;
                            _bracket = next < 1 ? null : next;
                          }),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(_bracket?.toString() ?? '-'),
                IconButton(
                  onPressed: () => setState(() {
                    _bracket = ((_bracket ?? 0) + 1).clamp(1, 5);
                  }),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isProxy,
              onChanged: (value) => setState(() => _isProxy = value ?? false),
              title: const Text('Enthält Proxy-Karten'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isTournamentLegal,
              onChanged: (value) =>
                  setState(() => _isTournamentLegal = value ?? true),
              title: const Text('Turnierlegal'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _deckLinkController,
              decoration: const InputDecoration(
                labelText: 'Online-Link zum Deck (optional)',
              ),
            ),
            if (isEditing) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final deckId = widget.existingDeck!.id;
                    // Umschalter statt Einbahnstraße: ein bereits
                    // archiviertes Deck lässt sich hier auch wieder
                    // reaktivieren (Nutzeranforderung "Wie sehe ich
                    // archivierte Daten?" - vorher gab es dafür keinen
                    // Weg, siehe ARCHITECTURE.md).
                    final archiveNow = !widget.existingDeck!.archived;
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).pop();
                    try {
                      await ref
                          .read(decksRepositoryProvider)
                          .setArchived(deckId, archiveNow);
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Fehler beim ${archiveNow ? 'Archivieren' : 'Reaktivieren'}: $e',
                          ),
                        ),
                      );
                    }
                  },
                  icon: Icon(
                    widget.existingDeck!.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  label: Text(
                    widget.existingDeck!.archived
                        ? 'Deck reaktivieren'
                        : 'Deck archivieren',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
