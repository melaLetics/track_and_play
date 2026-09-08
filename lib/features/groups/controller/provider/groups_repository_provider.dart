import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../../../database/provider/database_provider.dart';
import '../repository/groups_repository.dart';

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return GroupsRepository(db);
});

/// Alle nicht archivierten Gruppen - Basis für die Gruppen-Übersicht.
final allGroupsProvider = StreamProvider<List<Group>>((ref) {
  final repo = ref.watch(groupsRepositoryProvider);
  return repo.watchAllActive();
});

/// ALLE Gruppen inkl. archivierte - für den "Archivierte anzeigen"-
/// Umschalter auf GroupsOverviewScreen.
final allGroupsIncludingArchivedProvider = StreamProvider<List<Group>>((ref) {
  final repo = ref.watch(groupsRepositoryProvider);
  return repo.watchAll();
});

final groupMembersProvider =
    StreamProvider.family<List<Player>, int>((ref, groupId) {
  final repo = ref.watch(groupsRepositoryProvider);
  return repo.watchMembers(groupId);
});

final groupMemberCountProvider =
    StreamProvider.family<int, int>((ref, groupId) {
  final repo = ref.watch(groupsRepositoryProvider);
  return repo.watchMemberCount(groupId);
});

final groupByIdProvider = StreamProvider.family<Group?, int>((ref, groupId) {
  final repo = ref.watch(groupsRepositoryProvider);
  return repo.watchGroupById(groupId);
});
