import 'package:drift/drift.dart';

import '../../../../database/app_database.dart';

class GroupsRepository {
  final AppDatabase db;

  GroupsRepository(this.db);

  /// Nicht archivierte Gruppen (Standard-Ansicht in der Übersicht).
  Stream<List<Group>> watchAllActive() {
    final query = db.select(db.groups)..where((g) => g.archived.equals(false));
    return query.watch();
  }

  /// ALLE Gruppen inkl. archivierte - für den "Archivierte anzeigen"-
  /// Umschalter auf GroupsOverviewScreen (siehe ARCHITECTURE.md). Ohne
  /// diesen Umschalter waren archivierte Gruppen nirgends mehr
  /// sichtbar oder reaktivierbar.
  Stream<List<Group>> watchAll() => db.select(db.groups).watch();

  Future<int> createGroup(String name) {
    return db.into(db.groups).insert(GroupsCompanion.insert(name: name));
  }

  /// Legt eine Gruppe an und fügt direkt ein erstes Mitglied hinzu
  /// (typischerweise den Nutzer selbst) - atomar in einer Transaktion.
  Future<int> createGroupWithMember(String name, int memberPlayerId) {
    return db.transaction(() async {
      final groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: name));
      await db.into(db.playerGroupMemberships).insert(
            PlayerGroupMembershipsCompanion.insert(
              playerId: memberPlayerId,
              groupId: groupId,
            ),
          );
      return groupId;
    });
  }

  Future<void> renameGroup(int groupId, String newName) {
    return (db.update(db.groups)..where((g) => g.id.equals(groupId)))
        .write(GroupsCompanion(name: Value(newName)));
  }

  Future<void> setArchived(int groupId, bool archived) {
    return (db.update(db.groups)..where((g) => g.id.equals(groupId)))
        .write(GroupsCompanion(archived: Value(archived)));
  }

  Future<int> addMember(int groupId, int playerId) {
    return db.into(db.playerGroupMemberships).insert(
          PlayerGroupMembershipsCompanion.insert(
            playerId: playerId,
            groupId: groupId,
          ),
        );
  }

  Future<void> removeMember(int groupId, int playerId) {
    return (db.delete(db.playerGroupMemberships)
          ..where(
            (m) => m.groupId.equals(groupId) & m.playerId.equals(playerId),
          ))
        .go();
  }

  Stream<int> watchMemberCount(int groupId) {
    final query = db.select(db.playerGroupMemberships)
      ..where((m) => m.groupId.equals(groupId));
    return query.watch().map((rows) => rows.length);
  }

  /// Einzelne Gruppe nach id (z. B. für die Anzeige in der Partien-Historie).
  Stream<Group?> watchGroupById(int groupId) {
    final query = db.select(db.groups)..where((g) => g.id.equals(groupId));
    return query.watchSingleOrNull();
  }

  /// Mitglieder einer Gruppe als Player-Liste (Join über
  /// PlayerGroupMemberships).
  Stream<List<Player>> watchMembers(int groupId) {
    final query = db.select(db.players).join([
      innerJoin(
        db.playerGroupMemberships,
        db.playerGroupMemberships.playerId.equalsExp(db.players.id),
      ),
    ])
      ..where(db.playerGroupMemberships.groupId.equals(groupId));
    return query
        .watch()
        .map((rows) => rows.map((row) => row.readTable(db.players)).toList());
  }
}
