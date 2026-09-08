import 'package:drift/drift.dart';

import 'game_participants_table.dart';

/// Ein einzelner Lebenspunkte-Wechsel während einer live erfassten
/// Partie. Wird ausschließlich für Games mit entryMode == live
/// geschrieben (siehe Games.entryMode).
///
/// Aus dieser Tabelle lässt sich "First Blood" ableiten (der zeitlich
/// erste Eintrag mit delta < 0 über alle Teilnehmer einer Partie
/// hinweg) sowie später ein Lebenspunkte-Verlaufsdiagramm.
class LifeEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get gameParticipantId =>
      integer().references(GameParticipants, #id)();

  DateTimeColumn get occurredAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Änderung gegenüber dem vorherigen Stand (negativ = Schaden,
  /// positiv = Lebenspunkte-Gewinn).
  IntColumn get delta => integer()();

  /// Lebenspunkte-Stand NACH dieser Änderung (denormalisiert, damit
  /// der Verlauf ohne Aufsummieren aller deltas gerendert werden kann).
  IntColumn get resultingLife => integer()();
}
