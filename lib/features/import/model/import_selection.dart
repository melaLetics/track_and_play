import 'participant_override.dart';

/// Auswahl, welche Einträge aus einem eingelesenen ExportBundle
/// tatsächlich importiert werden sollen (nach Vorschau/Duplikat-Prüfung
/// im Import-Wizard, siehe ImportPreview/ImportService).
class ImportSelection {
  final Set<int> selectedPlayerIndexes;
  final Set<int> selectedDeckIndexes;
  final Set<int> selectedGroupIndexes;
  final Set<int> selectedGameIndexes;

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
    this.participantOverrides = const {},
  });

  ImportSelection copyWith({
    Set<int>? selectedPlayerIndexes,
    Set<int>? selectedDeckIndexes,
    Set<int>? selectedGroupIndexes,
    Set<int>? selectedGameIndexes,
    Map<int, Map<int, ParticipantOverride>>? participantOverrides,
  }) {
    return ImportSelection(
      selectedPlayerIndexes:
          selectedPlayerIndexes ?? this.selectedPlayerIndexes,
      selectedDeckIndexes: selectedDeckIndexes ?? this.selectedDeckIndexes,
      selectedGroupIndexes: selectedGroupIndexes ?? this.selectedGroupIndexes,
      selectedGameIndexes: selectedGameIndexes ?? this.selectedGameIndexes,
      participantOverrides: participantOverrides ?? this.participantOverrides,
    );
  }
}
