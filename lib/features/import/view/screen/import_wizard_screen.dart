import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../players/controller/provider/players_repository_provider.dart';
import '../../controller/provider/import_service_provider.dart';
import '../../model/import_preview.dart';
import '../../model/import_selection.dart';
import '../../model/import_warning.dart';
import '../../model/participant_override.dart';
import '../widgets/game_import_tile.dart';
import 'qr_scan_screen.dart';

enum _Step { source, preview, result }

/// Import-Wizard: Quelle wählen (Datei oder QR-Scan) -> Vorschau mit
/// Duplikat-Kennzeichnung -> Import ausführen -> Ergebnis. Siehe
/// ImportService für die eigentliche Logik (Parsing, automatischer
/// Namens-Abgleich, tatsächlicher Datenbank-Import).
class ImportWizardScreen extends ConsumerStatefulWidget {
  const ImportWizardScreen({super.key});

  @override
  ConsumerState<ImportWizardScreen> createState() =>
      _ImportWizardScreenState();
}

class _ImportWizardScreenState extends ConsumerState<ImportWizardScreen> {
  _Step _step = _Step.source;
  bool _isBusy = false;
  ImportPreview? _preview;
  ImportSelection _selection = const ImportSelection();
  ImportResult? _result;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daten importieren')),
      body: switch (_step) {
        _Step.source => _buildSourceStep(),
        _Step.preview => _buildPreviewStep(),
        _Step.result => _buildResultStep(),
      },
    );
  }

  Widget _buildSourceStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Wähle eine zuvor exportierte JSON-Datei aus oder scanne einen '
          'geteilten QR-Code (einzelnes Deck oder Spielerprofil).',
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _isBusy ? null : _pickFile,
          icon: const Icon(Icons.folder_open),
          label: const Text('Datei auswählen'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isBusy ? null : _scanQr,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('QR-Code scannen'),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _isBusy = false);
        return;
      }
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Datei konnte nicht gelesen werden.');
      }
      // Bewusst utf8.decode statt String.fromCharCodes: Letzteres bildet
      // jedes Byte 1:1 auf ein UTF-16-Codepoint ab statt Mehrbyte-UTF-8-
      // Sequenzen zu decodieren - Umlaute/ß wurden dadurch verstümmelt
      // angezeigt (Nutzerhinweis).
      await _loadRaw(utf8.decode(bytes));
    } catch (e) {
      setState(() {
        _error = 'Import fehlgeschlagen: $e';
        _isBusy = false;
      });
    }
  }

  Future<void> _scanQr() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null) {
      setState(() => _isBusy = false);
      return;
    }
    try {
      await _loadRaw(raw);
    } catch (e) {
      setState(() {
        _error = 'Import fehlgeschlagen: $e';
        _isBusy = false;
      });
    }
  }

  Future<void> _loadRaw(String raw) async {
    final service = ref.read(importServiceProvider);
    final bundle = service.parseBundle(raw);
    // Self-Player-Name VOR buildPreview auflösen (siehe
    // ImportService.buildPreview-Dartdoc): Partien ohne eigene
    // Teilnahme werden anhand dieses Namens bereits dort komplett aus
    // der Vorschau gefiltert, statt sie hier nur zu verstecken.
    final self = await ref.read(selfPlayerProvider.future);
    final preview =
        await service.buildPreview(bundle, selfPlayerName: self?.name);
    setState(() {
      _preview = preview;
      _selection = _reconcileSelection(preview, preview.defaultSelection);
      _step = _Step.preview;
      _isBusy = false;
    });
  }

  /// Hält Decks in der Auswahl konsistent zur aktuellen Spieler-
  /// Auswahl (mit dem Nutzer abgestimmte Ergänzung, nach dem Bugreport
  /// "abgewählte Spieler wirken sich nicht sichtbar auf Decks aus"):
  /// wird nach JEDER Änderung der Spieler-Auswahl erneut aufgerufen
  /// (und einmalig auf die initiale defaultSelection). Ein Deck ohne
  /// AUFLÖSBAREN Besitzer (siehe [_resolvableOwnerNames] - NICHT
  /// dasselbe wie "ausgewählt", siehe dort) würde beim Import ohnehin
  /// übersprungen (siehe ImportService.performImport - "Besitzer
  /// nicht importiert/gefunden"-Warnung) - wird hier aber zusätzlich
  /// schon in der Vorschau aus der Auswahl entfernt, damit das nicht
  /// erst nach dem Import als Hinweis auffällt (siehe _deckSection,
  /// dort zusätzlich als deaktivierte Checkbox mit Begründung
  /// sichtbar).
  ///
  /// Gruppen sind NICHT Teil dieses Abgleichs (anders als noch bis vor
  /// Kurzem): sie werden stattdessen bereits in
  /// ImportService.buildPreview hart auf Mitgliedschaft des eigenen
  /// Self-Players gefiltert (siehe dort) - unabhängig davon, welche
  /// anderen Spieler gerade zum Import ausgewählt sind, siehe
  /// ARCHITECTURE.md.
  ImportSelection _reconcileSelection(
    ImportPreview preview,
    ImportSelection selection,
  ) {
    final resolvableOwnerNames = _resolvableOwnerNames(preview, selection);
    final validDeckIndexes = selection.selectedDeckIndexes.where((i) {
      final owner = preview.bundle.decks[i].ownerName.toLowerCase();
      return resolvableOwnerNames.contains(owner);
    }).toSet();
    return selection.copyWith(selectedDeckIndexes: validDeckIndexes);
  }

  /// Spielernamen, auf die ein Deck-Besitzer beim Import erfolgreich
  /// aufgelöst werden könnte (siehe ImportService.performImport -
  /// `playerIdByName` wird dort zuerst mit dem GESAMTEN vorhandenen
  /// Datenbestand vorbelegt und erst danach um frisch importierte
  /// Spieler ergänzt): das sind zum einen die gerade zum Import
  /// ausgewählten Spieler, zum anderen aber auch bereits als Duplikat
  /// erkannte Spieler, die lokal schon existieren, OBWOHL sie hier
  /// standardmäßig NICHT ausgewählt sind (siehe
  /// ImportPreviewEntry.likelyDuplicate) - genau das war der
  /// gemeldete Bug: der eigene Self-Player ist praktisch immer ein
  /// solches Duplikat, seine eigenen Decks wurden dadurch fälschlich
  /// blockiert.
  Set<String> _resolvableOwnerNames(
    ImportPreview preview,
    ImportSelection selection,
  ) {
    return {
      for (var i = 0; i < preview.bundle.players.length; i++)
        if (selection.selectedPlayerIndexes.contains(i) ||
            preview.players[i].likelyDuplicate)
          preview.bundle.players[i].name.toLowerCase(),
    };
  }

  Widget _buildPreviewStep() {
    final preview = _preview!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (preview.players.isNotEmpty) _playerSection(preview),
              if (preview.bundle.groups.isNotEmpty) ...[
                if (preview.groups.isNotEmpty) _groupSection(preview),
                if (preview.bundle.groups.length > preview.groups.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${preview.bundle.groups.length - preview.groups.length} '
                      'Gruppe(n) ohne eigene Mitgliedschaft werden nicht '
                      'angezeigt/importiert.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
              ],
              if (preview.decks.isNotEmpty) _deckSection(preview),
              if (preview.bundle.games.isNotEmpty) ...[
                if (preview.games.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Partien (${_selection.selectedGameIndexes.length}/'
                      '${preview.games.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                if (preview.bundle.games.length > preview.games.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${preview.bundle.games.length - preview.games.length} '
                      'Partie(n) ohne eigene Teilnahme werden nicht '
                      'angezeigt/importiert.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                for (final entry in preview.games)
                  GameImportTile(
                    gameIndex: entry.index,
                    game: preview.bundle.games[entry.index],
                    entry: entry,
                    selected:
                        _selection.selectedGameIndexes.contains(entry.index),
                    onSelectedChanged: (checked) {
                      final next =
                          Set<int>.from(_selection.selectedGameIndexes);
                      if (checked) {
                        next.add(entry.index);
                      } else {
                        next.remove(entry.index);
                      }
                      setState(
                        () => _selection =
                            _selection.copyWith(selectedGameIndexes: next),
                      );
                    },
                    overrides:
                        _selection.participantOverrides[entry.index] ??
                            const {},
                    onOverrideChanged: (participantIndex, override) {
                      final gameOverrides = Map<int, ParticipantOverride>.from(
                        _selection.participantOverrides[entry.index] ??
                            const {},
                      );
                      gameOverrides[participantIndex] = override;
                      final allOverrides =
                          Map<int, Map<int, ParticipantOverride>>.from(
                        _selection.participantOverrides,
                      );
                      allOverrides[entry.index] = gameOverrides;
                      setState(
                        () => _selection = _selection.copyWith(
                          participantOverrides: allOverrides,
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _isBusy ? null : _performImport,
            icon: const Icon(Icons.check),
            label: Text(_isBusy ? 'Importiere…' : 'Importieren'),
          ),
        ),
      ],
    );
  }

  /// Wie [_section], aber Decks sind zusätzlich an die Spieler-Auswahl
  /// gekoppelt (mit dem Nutzer abgestimmte Ergänzung): ein Deck, dessen
  /// Besitzer aktuell NICHT ausgewählt ist, lässt sich hier gar nicht
  /// erst anhaken (Checkbox deaktiviert, mit Begründung als Untertitel) -
  /// es würde beim Import ohnehin übersprungen (siehe
  /// ImportService.performImport), das ist so aber schon in der
  /// Vorschau sichtbar statt erst hinterher als Warnung.
  Widget _deckSection(ImportPreview preview) {
    final resolvableOwnerNames = _resolvableOwnerNames(preview, _selection);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'Decks (${_selection.selectedDeckIndexes.length}/'
            '${preview.decks.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final entry in preview.decks)
          Builder(
            builder: (context) {
              final owner = preview.bundle.decks[entry.index].ownerName;
              final ownerResolvable =
                  resolvableOwnerNames.contains(owner.toLowerCase());
              final subtitleParts = <String>[
                if (entry.subtitle != null) entry.subtitle!,
                if (entry.likelyDuplicate) _deckDuplicateNote(entry),
                if (!ownerResolvable)
                  'Besitzer nicht ausgewählt/vorhanden - wird nicht '
                      'importiert',
              ];
              return CheckboxListTile(
                dense: true,
                title: Text(entry.title),
                subtitle: subtitleParts.isEmpty
                    ? null
                    : Text(subtitleParts.join(' · ')),
                value: ownerResolvable &&
                    _selection.selectedDeckIndexes.contains(entry.index),
                onChanged: !ownerResolvable
                    ? null
                    : (checked) =>
                        _onDeckCheckboxChanged(entry, checked ?? false),
              );
            },
          ),
      ],
    );
  }

  /// Untertitel-Zusatz für ein als Duplikat erkanntes Deck (siehe
  /// ImportPreviewEntry.likelyDuplicate) - unterscheidet, ob das
  /// bestehende lokale Deck inhaltlich identisch ist (dann wie bisher
  /// nur ein Hinweis) oder abweicht (dann Anzahl der Abweichungen
  /// bzw., falls der Nutzer im "Deck aktualisieren?"-Dialog bereits
  /// zugestimmt hat, dass es beim Import aktualisiert wird - siehe
  /// _onDeckCheckboxChanged/_confirmDeckMerge).
  String _deckDuplicateNote(ImportPreviewEntry entry) {
    if (entry.deckFieldDiffs.isEmpty) {
      return 'vermutlich bereits vorhanden';
    }
    final merging = _selection.mergeDeckIndexes.contains(entry.index);
    return merging
        ? 'wird aktualisiert (${entry.deckFieldDiffs.length} '
            'Abweichung(en) übernommen)'
        : 'vermutlich bereits vorhanden, weicht in '
            '${entry.deckFieldDiffs.length} Punkt(en) ab';
  }

  /// Reagiert auf das (Ab-)Wählen eines Deck-Eintrags. Wird ein bisher
  /// abgewähltes Duplikat mit tatsächlichen inhaltlichen Abweichungen
  /// (siehe ImportPreviewEntry.deckFieldDiffs) angehakt, wird zuerst
  /// per Dialog nachgefragt, ob die Werte aus dem Import übernommen
  /// werden sollen (siehe _confirmDeckMerge) - erst danach wird die
  /// Auswahl tatsächlich geändert. Ein identisches Duplikat (keine
  /// Abweichungen) verhält sich wie bisher (kein Dialog, einfacher
  /// Import als separater Datensatz). Ein Abbruch des Dialogs lässt
  /// die Auswahl unverändert; das Abwählen eines bereits zum
  /// Aktualisieren markierten Eintrags hebt die Merge-Markierung
  /// wieder auf.
  Future<void> _onDeckCheckboxChanged(
    ImportPreviewEntry entry,
    bool checked,
  ) async {
    final alreadySelected =
        _selection.selectedDeckIndexes.contains(entry.index);
    if (checked &&
        !alreadySelected &&
        entry.likelyDuplicate &&
        entry.deckFieldDiffs.isNotEmpty) {
      final merge = await _confirmDeckMerge(entry);
      if (merge == null) return;
      setState(() {
        final decks = Set<int>.from(_selection.selectedDeckIndexes)
          ..add(entry.index);
        final merges = Set<int>.from(_selection.mergeDeckIndexes);
        if (merge) {
          merges.add(entry.index);
        } else {
          merges.remove(entry.index);
        }
        _selection = _selection.copyWith(
          selectedDeckIndexes: decks,
          mergeDeckIndexes: merges,
        );
      });
      return;
    }
    setState(() {
      final decks = Set<int>.from(_selection.selectedDeckIndexes);
      final merges = Set<int>.from(_selection.mergeDeckIndexes);
      if (checked) {
        decks.add(entry.index);
      } else {
        decks.remove(entry.index);
        merges.remove(entry.index);
      }
      _selection = _selection.copyWith(
        selectedDeckIndexes: decks,
        mergeDeckIndexes: merges,
      );
    });
  }

  /// true = zusammenführen (das bestehende lokale Deck wird mit den
  /// abweichenden Werten aus dem Import überschrieben), false =
  /// separates neues Deck anlegen (wie bisheriges Verhalten), null =
  /// Dialog abgebrochen (siehe _onDeckCheckboxChanged).
  Future<bool?> _confirmDeckMerge(ImportPreviewEntry entry) {
    final existingLabel = entry.matchedExistingLabel ?? entry.title;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deck aktualisieren?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Das Deck "$existingLabel" existiert bereits, weicht aber '
                'vom Import ab:',
              ),
              const SizedBox(height: 8),
              for (final diff in entry.deckFieldDiffs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• $diff',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Sollen die Werte aus dem Import in das bestehende Deck '
                'übernommen werden?',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nein, separates Deck'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ja, aktualisieren'),
          ),
        ],
      ),
    );
  }

  /// Zeigt die Spieler-Auswahl - mit Sonderbehandlung für als
  /// Duplikat erkannte Einträge (siehe ImportPreviewEntry.
  /// likelyDuplicate): wird ein solcher Eintrag angehakt, erscheint
  /// zuerst der "gleiche Person?"-Dialog (siehe
  /// _onPlayerCheckboxChanged/_confirmPlayerMerge), damit Decks/
  /// Partien dieser Person wahlweise mit einer bereits bestehenden
  /// lokalen Person zusammengeführt statt eine weitere Person
  /// angelegt wird (mit dem Nutzer abgestimmte Ergänzung, Bugreport
  /// "es wird eine weitere Person angelegt").
  Widget _playerSection(ImportPreview preview) {
    final entries = preview.players;
    final selected = _selection.selectedPlayerIndexes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'Spieler (${selected.length}/${entries.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final entry in entries)
          CheckboxListTile(
            dense: true,
            title: Text(entry.title),
            subtitle: _playerSubtitle(entry),
            value: selected.contains(entry.index),
            onChanged: (checked) =>
                _onPlayerCheckboxChanged(preview, entry, checked ?? false),
          ),
      ],
    );
  }

  Widget? _playerSubtitle(ImportPreviewEntry entry) {
    final parts = <String>[
      if (entry.subtitle != null) entry.subtitle!,
    ];
    if (entry.likelyDuplicate) {
      final merged = _selection.mergePlayerIndexes.contains(entry.index);
      final existingLabel = entry.matchedExistingLabel ?? entry.title;
      parts.add(
        merged
            ? 'wird mit "$existingLabel" zusammengeführt'
            : 'vermutlich bereits vorhanden ("$existingLabel")',
      );
    }
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }

  /// Reagiert auf das (Ab-)Wählen eines Spieler-Eintrags. Wird ein
  /// bisher abgewählter Duplikat-Eintrag angehakt, wird zuerst per
  /// Dialog nachgefragt, ob es sich um dieselbe Person handelt (siehe
  /// _confirmPlayerMerge) - erst danach wird die Auswahl tatsächlich
  /// geändert. Ein Abbruch des Dialogs (Tippen daneben/"Abbrechen")
  /// lässt die Auswahl unverändert. Das Abwählen eines bereits
  /// zusammengeführten Eintrags hebt die Merge-Markierung wieder auf.
  Future<void> _onPlayerCheckboxChanged(
    ImportPreview preview,
    ImportPreviewEntry entry,
    bool checked,
  ) async {
    final alreadySelected =
        _selection.selectedPlayerIndexes.contains(entry.index);
    if (checked && !alreadySelected && entry.likelyDuplicate) {
      final merge = await _confirmPlayerMerge(entry);
      if (merge == null) return;
      setState(() {
        final players = Set<int>.from(_selection.selectedPlayerIndexes)
          ..add(entry.index);
        final merges = Set<int>.from(_selection.mergePlayerIndexes);
        if (merge) {
          merges.add(entry.index);
        } else {
          merges.remove(entry.index);
        }
        final updated = _selection.copyWith(
          selectedPlayerIndexes: players,
          mergePlayerIndexes: merges,
        );
        _selection = _reconcileSelection(preview, updated);
      });
      return;
    }
    setState(() {
      final players = Set<int>.from(_selection.selectedPlayerIndexes);
      final merges = Set<int>.from(_selection.mergePlayerIndexes);
      if (checked) {
        players.add(entry.index);
      } else {
        players.remove(entry.index);
        merges.remove(entry.index);
      }
      final updated = _selection.copyWith(
        selectedPlayerIndexes: players,
        mergePlayerIndexes: merges,
      );
      _selection = _reconcileSelection(preview, updated);
    });
  }

  /// true = zusammenführen (Merge), false = neue Person anlegen (wie
  /// bisheriges Verhalten), null = Dialog abgebrochen (siehe
  /// _onPlayerCheckboxChanged).
  Future<bool?> _confirmPlayerMerge(ImportPreviewEntry entry) {
    final existingLabel = entry.matchedExistingLabel ?? entry.title;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gleiche Person?'),
        content: Text(
          'Es existiert bereits eine Person namens "$existingLabel". '
          'Handelt es sich um dieselbe Person? Dann werden Decks und '
          'Partien beim Import mit dieser bestehenden Person '
          'zusammengeführt, statt eine weitere Person anzulegen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nein, neue Person'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ja, zusammenführen'),
          ),
        ],
      ),
    );
  }

  /// Zeigt die Gruppen-Auswahl - Verhalten jetzt bewusst identisch zu
  /// [_playerSection] (Nutzer-Feedback: die vorherige separate
  /// Sync-Icon-Variante hat "nicht geklappt"): wird ein als Duplikat
  /// erkannter Eintrag angehakt, erscheint zuerst der "gleiche
  /// Gruppe?"-Dialog (siehe _onGroupCheckboxChanged/
  /// _confirmGroupMerge), damit Mitglieder wahlweise mit einer bereits
  /// bestehenden lokalen Gruppe zusammengeführt statt eine weitere
  /// Gruppe angelegt wird.
  Widget _groupSection(ImportPreview preview) {
    final entries = preview.groups;
    final selected = _selection.selectedGroupIndexes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'Gruppen (${selected.length}/${entries.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final entry in entries)
          CheckboxListTile(
            dense: true,
            title: Text(entry.title),
            subtitle: _groupSubtitle(entry),
            value: selected.contains(entry.index),
            onChanged: (checked) =>
                _onGroupCheckboxChanged(preview, entry, checked ?? false),
          ),
      ],
    );
  }

  Widget? _groupSubtitle(ImportPreviewEntry entry) {
    final parts = <String>[
      if (entry.subtitle != null) entry.subtitle!,
    ];
    if (entry.likelyDuplicate) {
      final merged = _selection.mergeGroupIndexes.contains(entry.index);
      final existingLabel = entry.matchedExistingLabel ?? entry.title;
      parts.add(
        merged
            ? 'wird mit "$existingLabel" zusammengeführt'
            : 'vermutlich bereits vorhanden ("$existingLabel")',
      );
    }
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }

  /// Wie [_onPlayerCheckboxChanged], nur für Gruppen: Wird ein bisher
  /// abgewähltes Duplikat angehakt, wird zuerst per Dialog nachgefragt,
  /// ob es sich um dieselbe Gruppe handelt (siehe _confirmGroupMerge) -
  /// erst danach wird die Auswahl tatsächlich geändert. Ein Abbruch
  /// des Dialogs lässt die Auswahl unverändert. Das Abwählen einer
  /// bereits zusammengeführten Gruppe hebt die Merge-Markierung wieder
  /// auf.
  Future<void> _onGroupCheckboxChanged(
    ImportPreview preview,
    ImportPreviewEntry entry,
    bool checked,
  ) async {
    final alreadySelected =
        _selection.selectedGroupIndexes.contains(entry.index);
    if (checked && !alreadySelected && entry.likelyDuplicate) {
      final merge = await _confirmGroupMerge(entry);
      if (merge == null) return;
      setState(() {
        final groups = Set<int>.from(_selection.selectedGroupIndexes)
          ..add(entry.index);
        final merges = Set<int>.from(_selection.mergeGroupIndexes);
        if (merge) {
          merges.add(entry.index);
        } else {
          merges.remove(entry.index);
        }
        _selection = _selection.copyWith(
          selectedGroupIndexes: groups,
          mergeGroupIndexes: merges,
        );
      });
      return;
    }
    setState(() {
      final groups = Set<int>.from(_selection.selectedGroupIndexes);
      final merges = Set<int>.from(_selection.mergeGroupIndexes);
      if (checked) {
        groups.add(entry.index);
      } else {
        groups.remove(entry.index);
        merges.remove(entry.index);
      }
      _selection = _selection.copyWith(
        selectedGroupIndexes: groups,
        mergeGroupIndexes: merges,
      );
    });
  }

  /// true = zusammenführen (Merge, fehlende Mitglieder werden in die
  /// bestehende Gruppe übernommen), false = neue Gruppe anlegen (wie
  /// bisheriges Verhalten), null = Dialog abgebrochen (siehe
  /// _onGroupCheckboxChanged).
  Future<bool?> _confirmGroupMerge(ImportPreviewEntry entry) {
    final existingLabel = entry.matchedExistingLabel ?? entry.title;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gleiche Gruppe?'),
        content: Text(
          'Es existiert bereits eine Gruppe namens "$existingLabel". '
          'Handelt es sich um dieselbe Gruppe? Dann werden fehlende '
          'Mitglieder aus dem Import in diese bestehende Gruppe '
          'übernommen, statt eine weitere Gruppe anzulegen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nein, neue Gruppe'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ja, zusammenführen'),
          ),
        ],
      ),
    );
  }

  Future<void> _performImport() async {
    setState(() => _isBusy = true);
    final service = ref.read(importServiceProvider);
    final result = await service.performImport(_preview!.bundle, _selection);
    setState(() {
      _result = result;
      _step = _Step.result;
      _isBusy = false;
    });
  }

  Widget _buildResultStep() {
    final result = _result!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Import abgeschlossen: ${result.playersImported} Spieler, '
          '${result.decksImported} Decks, ${result.groupsImported} Gruppen, '
          '${result.gamesImported} Partien.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (result.playersMerged > 0 ||
            result.decksMerged > 0 ||
            result.groupsMerged > 0) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (result.playersMerged > 0)
                '${result.playersMerged} Spieler mit bestehenden Personen '
                    'zusammengeführt',
              if (result.decksMerged > 0)
                '${result.decksMerged} Decks aktualisiert',
              if (result.groupsMerged > 0)
                '${result.groupsMerged} Gruppen mit bestehenden Gruppen '
                    'zusammengeführt',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Hinweise', style: Theme.of(context).textTheme.titleSmall),
          for (final group in _groupWarnings(result.warnings))
            _WarningGroupTile(summary: group.$1, messages: group.$2),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fertig'),
        ),
      ],
    );
  }

  /// Fasst [warnings] je Kategorie zusammen (z. B. "3 Decks nicht
  /// importiert") statt sie als lange Einzelliste anzuzeigen - die
  /// vollständigen Meldungen bleiben über [_WarningGroupTile]
  /// aufklappbar erreichbar (mit dem Nutzer abgestimmte Vorgabe).
  /// Reihenfolge bewusst fest (Decks -> Teilnehmer -> Partien), damit
  /// sie sich zwischen Importen nicht unmotiviert ändert.
  List<(String, List<String>)> _groupWarnings(List<ImportWarning> warnings) {
    String plural(int n, String singular, String plural) =>
        n == 1 ? singular : plural;

    final byCategory = <ImportWarningCategory, List<String>>{};
    for (final w in warnings) {
      byCategory.putIfAbsent(w.category, () => []).add(w.message);
    }

    final result = <(String, List<String>)>[];
    final decks = byCategory[ImportWarningCategory.deck];
    if (decks != null && decks.isNotEmpty) {
      result.add((
        '${decks.length} ${plural(decks.length, 'Deck', 'Decks')} nicht '
            'importiert',
        decks,
      ));
    }
    final participants = byCategory[ImportWarningCategory.participant];
    if (participants != null && participants.isNotEmpty) {
      result.add((
        '${participants.length} Teilnehmer als anonym übernommen',
        participants,
      ));
    }
    final games = byCategory[ImportWarningCategory.game];
    if (games != null && games.isNotEmpty) {
      result.add((
        '${games.length} ${plural(games.length, 'Partie', 'Partien')} '
            'übersprungen',
        games,
      ));
    }
    return result;
  }
}

/// Ein zusammengefasster Hinweis-Block im Ergebnis-Schritt: standardmäßig
/// eingeklappt, mit den vollständigen Einzelmeldungen zum Aufklappen
/// (siehe _groupWarnings).
class _WarningGroupTile extends StatelessWidget {
  final String summary;
  final List<String> messages;

  const _WarningGroupTile({required this.summary, required this.messages});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
        title: Text(summary),
        children: [
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $message',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
