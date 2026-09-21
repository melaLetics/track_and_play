import 'package:drift/drift.dart';

import 'players_table.dart';

/// Bauart eines Decks - übernommen aus mtg_stats_tracker.
enum DeckBuildType { precon, upgraded, homebrew }

/// Etablierter Deck-Archetyp/Spielstil (z. B. "Aristocrats", "Voltron") -
/// orientiert an der von EDHREC/Moxfield fuer die Theme-Browser-Funktion
/// verwendeten Tag-Taxonomie (siehe ARCHITECTURE.md), aber bewusst auf
/// die im Commander-Umfeld etabliertesten ca. 45 Archetypen kuratiert
/// statt der vollen EDHREC-Liste (300+ Eintraege, die auch sehr
/// nischige Mechanik-Subthemes und Scherz-/Un-Set-Tags enthaelt und
/// fuer eine Einfachauswahl nicht sinnvoll waere). Feinere/seltenere
/// Subthemes koennen zusaetzlich frei in [Decks.subthemes] erfasst
/// werden.
enum DeckArchetype {
  aggro,
  midrange,
  control,
  combo,
  stax,
  voltron,
  aristocrats,
  spellslinger,
  reanimator,
  tokens,
  plusOneCounters,
  lifegain,
  lifedrain,
  ramp,
  landfall,
  landsMatter,
  artifacts,
  enchantress,
  equipment,
  vehicles,
  graveyard,
  selfMill,
  mill,
  groupHug,
  groupSlug,
  pillowFort,
  politics,
  storm,
  wheels,
  cardDraw,
  discard,
  blink,
  sacrifice,
  theft,
  bigMana,
  goodStuff,
  superfriends,
  tribal,
  infect,
  extraCombats,
  burn,
  tempo,
  hatebears,
  toolbox,
  monarch,
  treasure,
  food,
  devotion,
  prowess,
  cedh,
}

/// Ein Deck eines bekannt erfassten Spielers.
///
/// Analog zu Players: Decks unbekannter Spieler werden nicht hier
/// gespeichert, sondern inline auf GameParticipants.
class Decks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ownerPlayerId => integer().references(Players, #id)();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// Sortierte WUBRG-Buchstaben, z. B. "WU". Leerer String = farblos.
  TextColumn get colorIdentity =>
      text().withDefault(const Constant(''))();

  TextColumn get commanderName => text().nullable()();

  /// Partner-/zweiter Commander (z. B. bei "Partner"-Fähigkeit oder
  /// Background) - optional, unabhängig von commanderName.
  TextColumn get secondCommanderName => text().nullable()();

  /// Bauart des Decks (precon/upgraded/homebrew) - aus mtg_stats_tracker
  /// übernommen, dort als freies Dropdown ("Art des Decks").
  TextColumn get buildType => textEnum<DeckBuildType>().nullable()();

  /// Etablierter Archetyp/Spielstil des Decks (z. B. Aristocrats,
  /// Voltron) - optionale Auswahl aus [DeckArchetype] (Nutzerwunsch,
  /// angelehnt an die EDHREC/Moxfield-Theme-Taxonomie). Viele Decks
  /// lassen sich nicht auf EINEN Archetyp reduzieren (Nutzerwunsch-
  /// Erweiterung) - daher zusaetzlich [secondArchetype]/
  /// [thirdArchetype] fuer bis zu drei Archetypen pro Deck, analog zum
  /// bestehenden commanderName/secondCommanderName-Muster statt einer
  /// eigenen Mehrfachauswahl-Relationstabelle (gleiche Abwaegung wie
  /// bei [subthemes]: fuer eine feste Obergrenze von drei reichen drei
  /// einfache nullable Spalten). [secondArchetype]/[thirdArchetype]
  /// sind nur sinnvoll gesetzt, wenn die jeweils vorherige Spalte auch
  /// gesetzt ist (siehe DeckFormDialog), das wird aber nicht auf
  /// DB-Ebene erzwungen.
  TextColumn get archetype => textEnum<DeckArchetype>().nullable()();

  /// Zweiter Archetyp, siehe [archetype].
  TextColumn get secondArchetype => textEnum<DeckArchetype>().nullable()();

  /// Dritter Archetyp, siehe [archetype].
  TextColumn get thirdArchetype => textEnum<DeckArchetype>().nullable()();

  /// Weitere, feinere Subthemes als freier Text (z. B. "Ninjutsu,
  /// Clones, Extra Turns") - bewusst kein zweites Enum und keine
  /// Mehrfachauswahl-Relationstabelle: die volle EDHREC-Subtheme-Liste
  /// (300+ teils sehr nischige Eintraege) laesst sich dafuer nicht
  /// sinnvoll 1:1 abbilden (siehe ARCHITECTURE.md). Kommagetrennt als
  /// Konvention fuer die Anzeige, aber nicht strukturell erzwungen.
  TextColumn get subthemes => text().nullable()();

  /// Power-Level-Bracket (z. B. 1-5 nach dem WotC-Bracket-System) -
  /// optional, da nicht jeder das System nutzt.
  IntColumn get bracket => integer().nullable()();

  /// Enthält das Deck Proxy-Karten? Aus mtg_stats_tracker übernommen.
  BoolColumn get isProxy => boolean().withDefault(const Constant(false))();

  /// Ist das Deck turnierlegal (z. B. keine Proxies/Playtest-Karten)?
  /// Aus mtg_stats_tracker übernommen.
  BoolColumn get isTournamentLegal =>
      boolean().withDefault(const Constant(true))();

  /// Optionaler Link zur Deckliste (z. B. Moxfield/Archidekt).
  TextColumn get deckLink => text().nullable()();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
