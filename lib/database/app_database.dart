import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/players_table.dart';
import 'tables/decks_table.dart';
import 'tables/groups_table.dart';
import 'tables/player_group_memberships_table.dart';
import 'tables/games_table.dart';
import 'tables/game_participants_table.dart';
import 'tables/life_events_table.dart';

// Re-Export, damit Konsumenten (Repositories, UI) mit einem einzigen
// Import von app_database.dart sowohl die generierten Datenklassen als
// auch die in den Tabellen-Dateien definierten Enums (z. B. GameMode)
// bekommen, ohne die tables/*.dart-Dateien einzeln importieren zu müssen.
export 'tables/players_table.dart';
export 'tables/decks_table.dart';
export 'tables/groups_table.dart';
export 'tables/player_group_memberships_table.dart';
export 'tables/games_table.dart';
export 'tables/game_participants_table.dart';
export 'tables/life_events_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Players,
  Decks,
  Groups,
  PlayerGroupMemberships,
  Games,
  GameParticipants,
  LifeEvents,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'track_and_play');
}
