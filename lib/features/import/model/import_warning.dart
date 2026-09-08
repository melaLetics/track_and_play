/// Kategorie eines Hinweises aus [ImportResult.warnings] (siehe
/// import_preview.dart) - Grundlage für die zusammengefasste Anzeige
/// im Import-Wizard (ein Eintrag je Kategorie mit Anzahl, Details
/// aufklappbar) statt einer langen Einzelliste aller Meldungen.
enum ImportWarningCategory { deck, participant, game }

/// Ein einzelner Hinweis zu einem beim Import NICHT 1:1 übernommenen
/// Eintrag (siehe ImportService.performImport) - z. B. ein
/// übersprungenes Deck ohne auflösbaren Besitzer, ein mangels
/// bekanntem Spieler anonym übernommener Teilnehmer, oder eine wegen
/// unbekannten Modus übersprungene Partie.
class ImportWarning {
  final ImportWarningCategory category;
  final String message;

  const ImportWarning({required this.category, required this.message});
}
