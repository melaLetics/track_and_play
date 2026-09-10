import 'package:drift/drift.dart';

import 'games_table.dart';
import 'players_table.dart';
import 'decks_table.dart';

/// Ein Sitzplatz in einer Partie: entweder ein bekannter Spieler+Deck
/// (playerId/deckId gesetzt) ODER ein anonymer Teilnehmer, von dem
/// dauerhaft nur die Farbidentität (und optional ein loses Label)
/// bekannt ist (anonymousColorIdentity/anonymousLabel gesetzt).
///
/// Design-Entscheidung (siehe ARCHITECTURE.md): Anonyme Teilnehmer
/// werden NIE nachträglich zu Players/Decks-Zeilen hochgestuft - sie
/// bleiben für immer als Inline-Snapshot auf dieser Zeile.
class GameParticipants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get gameId => integer().references(Games, #id)();

  IntColumn get playerId => integer().nullable().references(Players, #id)();
  IntColumn get deckId => integer().nullable().references(Decks, #id)();

  TextColumn get anonymousLabel => text().nullable()();
  TextColumn get anonymousColorIdentity => text().nullable()();

  BoolColumn get isWinner => boolean().withDefault(const Constant(false))();
  IntColumn get placement => integer().nullable()();

  /// Team-/Rollen-Kennung: bei Two-Headed Giant der Teamname (z. B.
  /// "A"/"B"), bei Erzfeind entweder "archenemy" (genau ein Teilnehmer)
  /// oder "team" (alle anderen). Bei Commander/cEDH ungenutzt (null).
  TextColumn get team => text().nullable()();

  /// Start-Lebenspunkte dieses Teilnehmers. Nur bei Live-Erfassung
  /// gesetzt (z. B. 40 bei Commander, 20 bei anderen Formaten) -
  /// Grundlage für den Lebenspunkte-Verlauf in LifeEvents.
  IntColumn get startingLife => integer().nullable()();

  /// Zugreihenfolge/Sitzposition (1..Teilnehmerzahl), über alle
  /// Teilnehmer einer Partie hinweg eindeutig - auch in Team-Formaten,
  /// da jeder einzeln am Zug ist. Wird vor Spielbeginn festgelegt
  /// (siehe GameSetupScreen) und über den Validator geprüft.
  IntColumn get startPosition => integer().nullable()();

  /// Sitzplatz am Tisch für die Live-Ansicht (siehe TableSide) - rein
  /// für die Bildschirm-Anordnung/-Drehung in LiveGameScreen, hat mit
  /// der spielrelevanten Zugreihenfolge (siehe startPosition) nichts
  /// zu tun. Nur bei Live-Erfassung gesetzt, wird vor Spielbeginn im
  /// Setup über den Tisch-Diagramm-Wähler festgelegt.
  TextColumn get tableSide => textEnum<TableSide>().nullable()();
}
