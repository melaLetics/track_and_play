import 'package:drift/drift.dart';

import 'game_participants_table.dart';

/// Welcher der bis zu zwei Commander eines Decks (siehe
/// Decks.commanderName/secondCommanderName) den Schaden ausgeteilt hat.
enum CommanderSlot { primary, partner }

/// Ein einzelner Commander-Schaden-Eintrag während einer live erfassten
/// Partie (Nutzerwunsch: "Bekommt ein Spieler Commander Schaden, so
/// soll dieser ... den Commander auswählen ... und dort den Schaden
/// eintragen"). [gameParticipantId] ist der EMPFÄNGER des Schadens,
/// [sourceParticipantId] der Teilnehmer, dessen Commander/Partner-
/// Commander ([commanderSlot]) ihn ausgeteilt hat - beide logisch
/// dieselbe Partie, aber unterschiedliche Sitzplätze. Wird
/// ausschließlich für Games mit entryMode == live geschrieben (siehe
/// Games.entryMode), analog zu LifeEvents.
///
/// Jeder Eintrag hier erzeugt zusätzlich GENAU EINEN passenden
/// negativen LifeEvents-Eintrag (siehe
/// GamesRepository.recordCommanderDamage) - Commander-Schaden zieht
/// automatisch die Lebenspunkte ab (Nutzerwunsch), First Blood und die
/// Lebenspunkte-Historie funktionieren dadurch weiterhin
/// ausschließlich über LifeEvents, ohne Sonderfall.
class CommanderDamageEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Empfänger des Schadens.
  IntColumn get gameParticipantId =>
      integer().references(GameParticipants, #id)();

  /// Teilnehmer, dessen Commander ([commanderSlot]) den Schaden
  /// ausgeteilt hat.
  IntColumn get sourceParticipantId =>
      integer().references(GameParticipants, #id)();

  TextColumn get commanderSlot => textEnum<CommanderSlot>()();

  DateTimeColumn get occurredAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Änderung gegenüber dem vorherigen Stand DIESER Commander-Quelle
  /// (normalerweise positiv - Commander-Schaden steigt üblicherweise
  /// nur an; negativ nur zur Korrektur eines Fehleintrags).
  IntColumn get delta => integer()();

  /// Commander-Schaden-Stand DIESER Quelle NACH dieser Änderung
  /// (denormalisiert, analog zu LifeEvents.resultingLife - macht einen
  /// künftigen Verlauf ohne Aufsummieren aller deltas möglich).
  IntColumn get resultingCommanderDamage => integer()();
}
