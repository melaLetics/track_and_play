/// Leichtgewichtige Sicht auf eine Gruppe für Übersichts-/Auswahllisten
/// (z. B. Gruppenverwaltung, Filter im Statistik-Dashboard).
///
/// Die eigentliche CRUD-Logik (anlegen, Mitglieder hinzufügen/entfernen,
/// archivieren) folgt als nächster Implementierungsschritt gegen die
/// Groups/PlayerGroupMemberships-Tabellen.
class GroupMembershipSummary {
  final int groupId;
  final String groupName;
  final int memberCount;

  const GroupMembershipSummary({
    required this.groupId,
    required this.groupName,
    required this.memberCount,
  });
}
