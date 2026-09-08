import 'package:drift/drift.dart';

import 'players_table.dart';

/// Bauart eines Decks - übernommen aus mtg_stats_tracker.
enum DeckBuildType { precon, upgraded, homebrew }

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
