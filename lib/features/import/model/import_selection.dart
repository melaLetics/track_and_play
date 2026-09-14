import 'participant_override.dart';

/// Auswahl, welche Einträge aus einem eingelesenen ExportBundle
/// tatsächlich importiert werden sollen (nach Vorschau/Duplikat-Prüfung
/// im Import-Wizard, siehe ImportPreview/ImportService).
class ImportSelection {
  final Set<int> selectedPlayerIndexes;
  final Set<int> selectedDeckIndexes;
  final Set<int> selectedGroupIndexes;
  final Set<int> selectedGameIndexes;

  /// Indexe (in ExportBundle.players) von AUSGEWÄHLTEN Spielern, bei
  /// denen der Nutzer im "gleiche Person?"-Dialog (siehe
  /// ImportWizardScreen) bestätigt hat, dass es sich um dieselbe
  /// Person wie ein bereits bestehender lokaler Spieler handelt -
  /// ImportService.performImport überspringt für diese Indexe das
  /// Anlegen eines neuen Spieler-Datensatzes und ordnet Decks/Partien
  /// stattdessen dem bestehenden Spieler zu. Nur für Indexe relevant,
  /// die auch in [selectedPlayerIndexes] enthalten sind UND deren
  /// ImportPreviewEntry.likelyDuplicate true ist.
  final Set<int> mergePlayerIndexes;

  /// Indexe (in ExportBundle.groups) von AUSGEWÄHLTEN Gruppen, bei
  /// denen der Nutzer im "gleiche Gruppe?"-Dialog (siehe
  /// ImportWizardScreen) bestätigt hat, dass es sich um dieselbe
  /// Gruppe wie eine bereits bestehende lokale Gruppe handelt -
  /// spiegelbildlich zu [mergePlayerIndexes]. ImportService.
  /// performImport überspringt für diese Indexe das Anlegen einer
  /// neuen Gruppe und gleicht stattdessen fehlende Mitgliedschaften in
  /// die bestehende Gruppe ab. Nur für Indexe relevant, die auch in
  /// [selectedGroupIndexes] enthalten sind UND deren
  /// ImportPreviewEntry.likelyDuplicate true ist.
  final Set<int> mergeGroupIndexes;

  /// Indexe (in ExportBundle.decks) von AUSGEWÄHLTEN Decks, bei denen
  /// der Nutzer im "Deck aktualisieren?"-Dialog (siehe
  /// ImportWizardScreen) bestätigt hat, dass die abweichenden Werte
  /// aus dem Import in ein bereits bestehendes lokales Deck
  /// übernommen werden sollen (Nutzerwunsch: erkennt ein Spieler beim
  /// Teilen per QR-Code/Datei, dass sein Deck-Datensatz lokal schon
  /// existiert, aber inhaltlich abweicht - z. B. Commander, Farbe,
  /// Bracket, turnierlegal, Link, Proxy - wird gefragt, ob
  /// zusammengeführt werden soll). Anders als bei
  /// [mergePlayerIndexes]/[mergeGroupIndexes] bedeutet das Zusammen-
  /// führen hier NICHT nur "kein neuer Datensatz, bestehende id
  /// wiederverwendet", sondern zusätzlich, dass ImportService.
  /// performImport die inhaltlichen Felder des bestehenden Decks mit
  /// den Werten aus dem Import überschreibt. Nur für Indexe relevant,
  /// die auch in [selectedDeckIndexes] enthalten sind UND deren
  /// ImportPreviewEntry.deckFieldDiffs nicht leer ist (nur bei
  /// tatsächlicher Abweichung wird überhaupt nachgefragt, siehe
  /// ImportWizardScreen).
  final Set<int> mergeDeckIndexes;

  /// Manuelle "on the fly"-Übersteuerungen einzelner Partie-Teilnehmer
  /// (siehe ParticipantOverride/GameImportTile) - Partie-Index (Index
  /// in ExportBundle.games) -> Teilnehmer-Index (Index in
  /// GameExport.participants) -> Übersteuerung. Ein Eintrag existiert
  /// nur, wenn der Nutzer für diesen Teilnehmer explizit von der
  /// automatischen Namens-Auflösung abgewichen ist.
  final Map<int, Map<int, ParticipantOverride>> participantOverrides;

  const ImportSelection({
    this.selectedPlayerIndexes = const {},
    this.selectedDeckIndexes = const {},
    this.selectedGroupIndexes = const {},
    this.selectedGameIndexes = const {},
    this.mergePlayerIndexes = const {},
    this.mergeGroupIndexes = const {},
    this.mergeDeckIndexes = const {},
    this.participantOverrides = const {},
  });

  ImportSelection copyWith({
    Set<int>? selectedPlayerIndexes,
    Set<int>? selectedDeckIndexes,
    Set<int>? selectedGroupIndexes,
    Set<int>? selectedGameIndexes,
    Set<int>? mergePlayerIndexes,
    Set<int>? mergeGroupIndexes,
    Set<int>? mergeDeckIndexes,
    Map<int, Map<int, ParticipantOverride>>? participantOverrides,
  }) {
    return ImportSelection(
      selectedPlayerIndexes:
          selectedPlayerIndexes ?? this.selectedPlayerIndexes,
      selectedDeckIndexes: selectedDeckIndexes ?? this.selectedDeckIndexes,
      selectedGroupIndexes: selectedGroupIndexes ?? this.selectedGroupIndexes,
      selectedGameIndexes: selectedGameIndexes ?? this.selectedGameIndexes,
      mergePlayerIndexes: mergePlayerIndexes ?? this.mergePlayerIndexes,
      mergeGroupIndexes: mergeGroupIndexes ?? this.mergeGroupIndexes,
      mergeDeckIndexes: mergeDeckIndexes ?? this.mergeDeckIndexes,
      participantOverrides: participantOverrides ?? this.participantOverrides,
    );
  }
}
