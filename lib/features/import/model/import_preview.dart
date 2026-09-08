import '../../export/model/export_bundle.dart';
import 'import_selection.dart';
import 'import_warning.dart';

/// Ein einzelner Eintrag in der Import-Vorschau (siehe
/// ImportWizardScreen) - ein Bundle-Eintrag plus Anzeige-Infos.
class ImportPreviewEntry {
  final int index;
  final String title;
  final String? subtitle;

  /// Automatischer Namens-Abgleich (siehe ImportService.buildPreview):
  /// true, wenn bereits ein Eintrag mit demselben Namen existiert -
  /// dann standardmäßig ABGEWÄHLT. Bei Partien immer false (siehe
  /// ImportService-Klassendokumentation - dort standardmäßig
  /// AUSGEWÄHLT, aber ohne automatischen Abgleich).
  final bool likelyDuplicate;

  const ImportPreviewEntry({
    required this.index,
    required this.title,
    this.subtitle,
    this.likelyDuplicate = false,
  });
}

/// Ergebnis von ImportService.buildPreview: aufbereitete
/// Vorschau-Listen je Kategorie sowie eine mit dem Namens-Abgleich
/// vorausgewählte [ImportSelection].
class ImportPreview {
  final ExportBundle bundle;
  final List<ImportPreviewEntry> players;
  final List<ImportPreviewEntry> decks;
  final List<ImportPreviewEntry> groups;
  final List<ImportPreviewEntry> games;
  final ImportSelection defaultSelection;

  const ImportPreview({
    required this.bundle,
    required this.players,
    required this.decks,
    required this.groups,
    required this.games,
    required this.defaultSelection,
  });
}

/// Ergebnis von ImportService.performImport: Anzahl tatsächlich
/// angelegter Einträge je Kategorie sowie Hinweise zu Einträgen, die
/// nicht 1:1 übernommen werden konnten (z. B. ein Deck ohne
/// auflösbaren Besitzer, siehe ImportService).
class ImportResult {
  final int playersImported;
  final int decksImported;
  final int groupsImported;
  final int gamesImported;
  final List<ImportWarning> warnings;

  const ImportResult({
    this.playersImported = 0,
    this.decksImported = 0,
    this.groupsImported = 0,
    this.gamesImported = 0,
    this.warnings = const [],
  });
}
