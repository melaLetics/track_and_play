/// Auswahl, welche Datenkategorien beim Datei-Export enthalten sein
/// sollen (Basis-Auswahl im Export-Wizard, siehe ExportWizardScreen).
/// Gilt nur für den Datei-Export - der QR-Export ist auf ein einzelnes
/// Deck oder einen einzelnen Spieler beschränkt und braucht keine
/// Kategorie-Auswahl (siehe ExportService.buildDeckQrBundle/
/// buildPlayerQrBundle).
class ExportSelection {
  final bool includePlayers;
  final bool includeDecks;
  final bool includeGroups;
  final bool includeGames;

  const ExportSelection({
    this.includePlayers = true,
    this.includeDecks = true,
    this.includeGroups = true,
    this.includeGames = true,
  });

  ExportSelection copyWith({
    bool? includePlayers,
    bool? includeDecks,
    bool? includeGroups,
    bool? includeGames,
  }) {
    return ExportSelection(
      includePlayers: includePlayers ?? this.includePlayers,
      includeDecks: includeDecks ?? this.includeDecks,
      includeGroups: includeGroups ?? this.includeGroups,
      includeGames: includeGames ?? this.includeGames,
    );
  }
}
