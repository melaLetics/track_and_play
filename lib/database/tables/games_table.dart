import 'package:drift/drift.dart';

import 'groups_table.dart';

/// Spielformat einer Partie.
/// - commander: klassisches, ungewertetes Commander/EDH
/// - competitiveCommander: cEDH (kompetitives Commander mit höherem
///   Powerlevel/Turbo-Strategien) - gleiche Teilnehmer-/Datenstruktur
///   wie commander, daher kein eigenes Datenmodell nötig, nur ein
///   weiterer Modus-Wert.
/// - twoHeadedGiant / archenemy: eigene Team-/Rollen-Strukturen.
enum GameMode { commander, competitiveCommander, twoHeadedGiant, archenemy }

/// Wie eine Partie erfasst wurde:
/// - manual: nachträglich eingetragen (z. B. am nächsten Tag)
/// - live: während der Partie live erfasst, inkl. Lebenspunktezähler,
///   Dauer-Messung und First-Blood-Ermittlung (siehe LifeEvents).
enum GameEntryMode { manual, live }

/// Status einer live erfassten Partie. Manuell nachgetragene Partien
/// werden immer direkt als [completed] angelegt.
enum GameStatus { inProgress, completed }

class Games extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get playedAt => dateTime()();
  TextColumn get mode => textEnum<GameMode>()();
  TextColumn get notes => text().nullable()();

  /// Optional: welcher Spielgruppe diese Partie zugeordnet ist.
  /// Bleibt null für rein persönlich erfasste Partien ohne Gruppenbezug
  /// (Solo-Nutzung ohne jede Gruppe funktioniert damit unverändert).
  IntColumn get groupId => integer().nullable().references(Groups, #id)();

  TextColumn get entryMode => textEnum<GameEntryMode>()();
  TextColumn get status => textEnum<GameStatus>()();

  /// Nur bei entryMode == live gesetzt: Startzeitpunkt der
  /// Live-Erfassung, damit die Dauer auch nach einem App-Neustart
  /// weiterberechnet werden kann (Partie könnte im Hintergrund laufen).
  DateTimeColumn get startedAt => dateTime().nullable()();

  /// Gesamtdauer der Partie in Sekunden. Wird bei Live-Erfassung beim
  /// Beenden automatisch gesetzt; bei manuellem Nachtragen optional
  /// (falls der Nutzer sie ungefähr kennt).
  IntColumn get durationSeconds => integer().nullable()();

  /// Logischer Verweis auf GameParticipants.id (bewusst KEINE
  /// Drift-Foreign-Key-Referenz: GameParticipants verweist bereits per
  /// gameId auf Games - ein zyklischer FK zwischen beiden Tabellen
  /// würde die Modellierung unnötig verkomplizieren, ohne echten
  /// Mehrwert). Wird nur bei Live-Erfassung gesetzt, sobald ein
  /// Teilnehmer als erster Lebenspunkte verliert - siehe LifeEvents.
  IntColumn get firstBloodParticipantId => integer().nullable()();

  /// Unentschieden - alle (bzw. beide Seiten bei Team-Formaten)
  /// belegen denselben Platz. Siehe game_setup_validator.dart für die
  /// genauen Platzierungsregeln je Modus.
  BoolColumn get isDraw => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
