import '../../../database/app_database.dart';

/// Anzeige-Namen für TableSide - zentral gepflegt, damit der
/// Sitzplatz-Wähler (GameSetupScreen) und ggf. weitere Stellen
/// denselben Text verwenden.
const Map<TableSide, String> tableSideLabels = {
  TableSide.top: 'Oben',
  TableSide.bottom: 'Unten',
  TableSide.left: 'Links',
  TableSide.right: 'Rechts',
};
