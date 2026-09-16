import '../../../database/app_database.dart';

/// Sortiert eine bereits EINER Tischseite zugeordnete Teilnehmerliste
/// so, dass die Startreihenfolge (Zugreihenfolge) im Uhrzeigersinn
/// entlang dieser Seite verläuft (Nutzerwunsch: "Man spielt im
/// Uhrzeigersinn, so dass Person 1 rechts von Person 2 sitzt usw.").
///
/// **Geometrie-Herleitung** (Vogelperspektive, wie im Setup-Wähler und
/// im Live-Grid gezeichnet - siehe _TableSeatPicker/_LifeGrid): bei
/// jedem Spieler sitzt der im Uhrzeigersinn NÄCHSTE Mitspieler aus
/// dessen eigener, zum Tisch (zur Mitte) gewandter Perspektive IMMER
/// an dessen LINKER Seite - das ist die Standard-Konvention für "im
/// Uhrzeigersinn gespielt". Äquivalent dazu sitzt der VORHERIGE Spieler
/// (frühere Zugnummer) an dessen RECHTER Seite - exakt die vom Nutzer
/// genannte Regel. Übersetzt auf Bildschirm-Koordinaten (jede Seite
/// schaut zur Tischmitte, siehe RotatedBox-Drehung je Seite in
/// _LifeGrid) ergibt sich je Tischseite eine feste Sortierrichtung für
/// aufsteigende Zugreihenfolge:
/// - unten (unrotiert, blickt nach oben): links des Spielers = Bildschirm-
///   WESTEN -> aufsteigende Zugreihenfolge verläuft von RECHTS nach LINKS.
/// - links (blickt nach rechts/Osten): links des Spielers = Bildschirm-
///   NORDEN -> aufsteigende Zugreihenfolge verläuft von UNTEN nach OBEN.
/// - oben (blickt nach unten/Süden, 180°-gedreht): links des Spielers =
///   Bildschirm-OSTEN -> aufsteigende Zugreihenfolge verläuft von LINKS
///   nach RECHTS.
/// - rechts (blickt nach links/Westen): links des Spielers = Bildschirm-
///   SÜDEN -> aufsteigende Zugreihenfolge verläuft von OBEN nach UNTEN.
///
/// `_row`/`_column` (bzw. die Zonen-Wraps im Setup-Wähler) rendern
/// Listen immer in EINGABE-Reihenfolge links->rechts bzw. oben->unten -
/// daher wird hier zurückgegeben:
/// - oben/rechts: aufsteigend nach Startposition sortiert.
/// - unten/links: ABSTEIGEND nach Startposition sortiert (damit die
///   aufsteigende Zugreihenfolge visuell in die jeweils andere
///   Richtung läuft, siehe Herleitung oben).
///
/// Teilnehmer ohne Startposition (`null`, sollte praktisch nicht
/// vorkommen) werden stabil ans Ende sortiert.
List<T> sortForTableSide<T>(
  List<T> participants,
  TableSide side,
  int? Function(T participant) startPositionOf,
) {
  final sorted = [...participants];
  final ascending = side == TableSide.top || side == TableSide.right;
  sorted.sort((a, b) {
    final posA = startPositionOf(a);
    final posB = startPositionOf(b);
    if (posA == null && posB == null) return 0;
    if (posA == null) return 1;
    if (posB == null) return -1;
    return ascending ? posA.compareTo(posB) : posB.compareTo(posA);
  });
  return sorted;
}
