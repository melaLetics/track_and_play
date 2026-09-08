import '../../../database/app_database.dart';

/// Anzeige-Namen für DeckBuildType - zentral gepflegt für Dropdown und
/// Deck-Anzeige.
const Map<DeckBuildType, String> deckBuildTypeLabels = {
  DeckBuildType.precon: 'Precon',
  DeckBuildType.upgraded: 'Precon (aufgewertet)',
  DeckBuildType.homebrew: 'Eigenbau',
};
