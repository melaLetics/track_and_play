import 'package:drift/drift.dart';

/// Eine eigene Spielgruppe (z. B. "Freitagsrunde", "Familienrunde").
///
/// Gruppen sind rein optional: Wer nur die eigenen Partien erfassen
/// möchte, muss nie eine Gruppe anlegen - siehe AppSettings.trackOtherPlayers
/// und Games.groupId (nullable).
class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
