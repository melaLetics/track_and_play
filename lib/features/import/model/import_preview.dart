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

  /// Anzeigename des bereits bestehenden lokalen Eintrags, den
  /// [likelyDuplicate] als Duplikat erkannt hat (Namens-Abgleich ist
  /// case-insensitive - dieser Name kann sich daher in der
  /// Schreibweise vom importierten [title] unterscheiden). Nur bei
  /// Spielern und Gruppen gesetzt (siehe ImportService.buildPreview) -
  /// wird für den "gleiche Person?"/"gleiche Gruppe?"-Abgleichsdialog
  /// im ImportWizardScreen benötigt (siehe dort).
  final String? matchedExistingLabel;

  /// NUR bei Decks gesetzt (siehe ImportService.buildPreview/
  /// _deckFieldDiffs): menschlich lesbare Beschreibung jedes
  /// inhaltlichen Feldes, in dem sich ein als Duplikat erkanntes Deck
  /// (siehe [likelyDuplicate]/[matchedExistingLabel]) vom bereits
  /// bestehenden lokalen Deck unterscheidet (z. B. "Commander: Alela →
  /// Atraxa") - Grundlage für den "Deck aktualisieren?"-Abgleichsdialog
  /// im ImportWizardScreen (Nutzerwunsch: bei geteilten überarbeiteten
  /// Decks erkennen, WAS sich geändert hat, und optional übernehmen
  /// können). Leer, wenn kein Duplikat oder das Duplikat inhaltlich
  /// identisch ist.
  final List<String> deckFieldDiffs;

  const ImportPreviewEntry({
    required this.index,
    required this.title,
    this.subtitle,
    this.likelyDuplicate = false,
    this.matchedExistingLabel,
    this.deckFieldDiffs = const [],
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

  /// Anzahl der Spieler, die NICHT als neue Person angelegt, sondern
  /// (nach Bestätigung im "gleiche Person?"-Dialog, siehe
  /// ImportWizardScreen/ImportSelection.mergePlayerIndexes) mit einer
  /// bereits bestehenden lokalen Person zusammengeführt wurden - in
  /// [playersImported] NICHT enthalten, da kein neuer Datensatz
  /// entstanden ist.
  final int playersMerged;

  /// Anzahl der Decks, die NICHT als neues Deck angelegt, sondern
  /// (nach Bestätigung im "Deck aktualisieren?"-Dialog, siehe
  /// ImportWizardScreen/ImportSelection.mergeDeckIndexes) mit einem
  /// bereits bestehenden lokalen Deck zusammengeführt wurden - in
  /// [decksImported] NICHT enthalten. Anders als bei Spielern/Gruppen
  /// bedeutet "zusammengeführt" hier NICHT nur "kein neuer Datensatz,
  /// bestehende id wiederverwendet", sondern zusätzlich: die
  /// inhaltlichen Felder des bestehenden Decks wurden mit den (ggf.
  /// abweichenden) Werten aus dem Import überschrieben - siehe
  /// ImportService.performImport.
  final int decksMerged;

  /// Anzahl der Gruppen, die NICHT als neue Gruppe angelegt, sondern
  /// (nach Bestätigung im "gleiche Gruppe?"-Dialog, siehe
  /// ImportSelection.mergeGroupIndexes) mit einer bereits bestehenden
  /// lokalen Gruppe zusammengeführt wurden - in [groupsImported]
  /// NICHT enthalten, da kein neuer Datensatz entstanden ist; fehlende
  /// Mitgliedschaften wurden dabei in die bestehende Gruppe
  /// übernommen.
  final int groupsMerged;

  final List<ImportWarning> warnings;

  const ImportResult({
    this.playersImported = 0,
    this.decksImported = 0,
    this.groupsImported = 0,
    this.gamesImported = 0,
    this.playersMerged = 0,
    this.decksMerged = 0,
    this.groupsMerged = 0,
    this.warnings = const [],
  });
}
