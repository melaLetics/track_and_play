import '../../../database/app_database.dart';

/// Anzeige-Namen für GameMode - zentral gepflegt, damit Dropdown,
/// Historie und Detailansicht denselben Text verwenden.
const Map<GameMode, String> gameModeLabels = {
  GameMode.commander: 'Commander (EDH)',
  GameMode.competitiveCommander: 'Commander (cEDH)',
  GameMode.twoHeadedGiant: 'Two-Headed Giant',
  GameMode.archenemy: 'Archenemy',
};
