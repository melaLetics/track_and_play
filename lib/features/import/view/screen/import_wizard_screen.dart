import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final preview = await service.buildPreview(bundle);
    setState(() {
      _preview = preview;
      _selection = preview.defaultSelection;
      _step = _Step.preview;
      _isBusy = false;
    });
  }

  Widget _buildPreviewStep() {
    final preview = _preview!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (preview.players.isNotEmpty)
                _section(
                  'Spieler',
                  preview.players,
                  _selection.selectedPlayerIndexes,
                  (s) => setState(
                    () =>
                        _selection = _selection.copyWith(selectedPlayerIndexes: s),
                  ),
                ),
              if (preview.decks.isNotEmpty)
                _section(
                  'Decks',
                  preview.decks,
                  _selection.selectedDeckIndexes,
                  (s) => setState(
                    () => _selection = _selection.copyWith(selectedDeckIndexes: s),
                  ),
                ),
              if (preview.groups.isNotEmpty)
                _section(
                  'Gruppen',
                  preview.groups,
                  _selection.selectedGroupIndexes,
                  (s) => setState(
                    () =>
                        _selection = _selection.copyWith(selectedGroupIndexes: s),
                  ),
                ),
              if (preview.games.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    'Partien (${_selection.selectedGameIndexes.length}/'
                    '${preview.games.length})',
                    style: Theme.of(context).textTheme.titleMedium,
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

  Widget _section(
    String title,
    List<ImportPreviewEntry> entries,
    Set<int> selected,
    ValueChanged<Set<int>> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            '$title (${selected.length}/${entries.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final entry in entries)
          CheckboxListTile(
            dense: true,
            title: Text(entry.title),
            subtitle: entry.likelyDuplicate
                ? Text(
                    '${entry.subtitle != null ? '${entry.subtitle} · ' : ''}'
                    'vermutlich bereits vorhanden',
                  )
                : (entry.subtitle != null ? Text(entry.subtitle!) : null),
            value: selected.contains(entry.index),
            onChanged: (checked) {
              final next = Set<int>.from(selected);
              if (checked ?? false) {
                next.add(entry.index);
              } else {
                next.remove(entry.index);
              }
              onChanged(next);
            },
          ),
      ],
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
