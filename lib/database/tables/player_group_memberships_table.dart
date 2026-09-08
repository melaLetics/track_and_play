import 'package:drift/drift.dart';

import 'players_table.dart';
import 'groups_table.dart';

/// Many-to-many-Zuordnung zwischen Players und Groups.
///
/// Ein Player kann in keiner, einer oder mehreren Gruppen Mitglied sein
/// (z. B. spielt man selbst in mehreren Runden mit, ein Freund evtl.
/// nur in einer). Ein Player ohne jede Mitgliedschaft ist schlicht
/// noch keiner Gruppe zugeordnet (z. B. im reinen Solo-Betrieb).
class PlayerGroupMemberships extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playerId => integer().references(Players, #id)();
  IntColumn get groupId => integer().references(Groups, #id)();
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {playerId, groupId},
      ];
}
