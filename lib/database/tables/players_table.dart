import 'package:drift/drift.dart';

/// Ein Spieler, den der Nutzer dauerhaft erfasst - entweder er selbst
/// (isSelf = true, es gibt genau einen solchen Datensatz) oder ein
/// Mitspieler der eigenen Gruppe.
///
/// Unbekannte Mitspieler aus spontanen Partien werden NICHT hier
/// abgelegt, sondern bleiben inline auf GameParticipants (siehe dort).
class Players extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  BoolColumn get isSelf => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
