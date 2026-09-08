import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/rename_dialog.dart';
import '../../controller/provider/groups_repository_provider.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import '../../../players/view/screen/player_detail_screen.dart';

class GroupDetailScreen extends ConsumerWidget {
  final int groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    // Reaktiv statt per await abgefragt: eine vorherige Version wartete
    // hier per `await ref.read(groupByIdProvider(groupId).future)`, bevor
    // der Dialog geöffnet wurde - das ist derselbe Fehlerklasse wie beim
    // zuvor kaputten "Mitglied hinzufügen"-Button (Fire-and-forget-
    // Aufruf aus onSelected/onPressed heraus + ein davor liegender await,
    // der bei einem Fehler lautlos scheitert, ohne dass der Dialog je
    // erscheint). Mit ref.watch ist der aktuelle Gruppenname beim Tippen
    // auf "Umbenennen" bereits synchron vorhanden.
    final groupAsync = ref.watch(groupByIdProvider(groupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruppendetails'),
        actions: [
          groupAsync.maybeWhen(
            data: (group) {
              if (group == null) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'rename') {
                    showRenameDialog(
                      context,
                      title: 'Gruppe umbenennen',
                      currentName: group.name,
                      label: 'Neuer Name',
                      // Muss zur Groups.name-Spaltenbegrenzung passen
                      // (siehe groups_table.dart, withLength(max: 60)).
                      maxLength: 60,
                      onSave: (name) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(groupsRepositoryProvider)
                              .renameGroup(groupId, name);
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Fehler beim Speichern: $e')),
                          );
                        }
                      },
                    );
                  } else if (value == 'archive') {
                    // Umschalter statt Einbahnstraße - siehe
                    // deck_form_dialog.dart/player_detail_screen.dart
                    // für dieselbe Ergänzung bei Decks/Spielern.
                    final archiveNow = !group.archived;
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    try {
                      await ref
                          .read(groupsRepositoryProvider)
                          .setArchived(groupId, archiveNow);
                      // Nur beim Archivieren zurück zur Übersicht (wie
                      // bisher) - beim Reaktivieren bewusst auf der
                      // Detailseite bleiben, damit das Ergebnis direkt
                      // sichtbar ist.
                      if (archiveNow) navigator.pop();
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Fehler beim ${archiveNow ? 'Archivieren' : 'Reaktivieren'}: $e',
                          ),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Umbenennen'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      group.archived ? 'Reaktivieren' : 'Archivieren',
                    ),
                  ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
        data: (members) {
          if (members.isEmpty) {
            return const Center(child: Text('Noch keine Mitglieder.'));
          }
          return ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              final initial = member.name.isNotEmpty
                  ? member.name.substring(0, 1).toUpperCase()
                  : '?';
              return Opacity(
                opacity: member.archived ? 0.6 : 1,
                child: ListTile(
                  leading: CircleAvatar(child: Text(initial)),
                  title: Text(
                    member.isSelf ? '${member.name} (Ich)' : member.name,
                  ),
                  subtitle: Text(
                    member.archived
                        ? 'Archiviert · Antippen für Decks/Details'
                        : 'Antippen für Decks/Details',
                  ),
                  trailing: member.isSelf
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Aus Gruppe entfernen',
                          onPressed: () async {
                            await ref
                                .read(groupsRepositoryProvider)
                                .removeMember(groupId, member.id);
                          },
                        ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlayerDetailScreen(playerId: member.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'group_detail_fab',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _AddMemberDialog(groupId: groupId),
        ),
        tooltip: 'Mitglied hinzufügen',
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

/// Dialog zum Hinzufügen eines Gruppenmitglieds: entweder ein bereits
/// bekannter, noch nicht in der Gruppe befindlicher Spieler, oder ein
/// direkt neu angelegter. Als eigenes ConsumerStatefulWidget umgesetzt
/// (statt einer Funktion mit manuell verwaltetem TextEditingController),
/// damit sowohl der Controller korrekt über initState/dispose verwaltet
/// wird (siehe rename_dialog.dart für die ausführliche Begründung) als
/// auch die Kandidatenliste live per ref.watch aktuell bleibt, statt
/// einmalig vor dem Öffnen abgefragt zu werden.
class _AddMemberDialog extends ConsumerStatefulWidget {
  final int groupId;

  const _AddMemberDialog({required this.groupId});

  @override
  ConsumerState<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<_AddMemberDialog> {
  late final TextEditingController _newPlayerNameController;

  /// Bezieht auch bereits archivierte Spieler in die Kandidatenliste
  /// ein - der einzige Weg, einen Spieler wiederzufinden, der aktuell
  /// in KEINER Gruppe mehr Mitglied ist (siehe ARCHITECTURE.md,
  /// Nutzeranforderung "Wie sehe ich archivierte Daten?"). Erneutes
  /// Hinzufügen macht ihn wieder über die Mitgliederliste erreichbar
  /// (dort als "archiviert" markiert), reaktivieren lässt er sich dann
  /// auf seinem PlayerDetailScreen.
  bool _includeArchived = false;

  @override
  void initState() {
    super.initState();
    _newPlayerNameController = TextEditingController();
  }

  @override
  void dispose() {
    _newPlayerNameController.dispose();
    super.dispose();
  }

  Future<void> _addExisting(int playerId) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await ref
          .read(groupsRepositoryProvider)
          .addMember(widget.groupId, playerId);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler beim Hinzufügen: $e')),
      );
    }
  }

  Future<void> _createAndAdd() async {
    final name = _newPlayerNameController.text.trim();
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final groupId = widget.groupId;
    Navigator.of(context).pop();
    try {
      final newId = await ref.read(playersRepositoryProvider).createPlayer(name);
      await ref.read(groupsRepositoryProvider).addMember(groupId, newId);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler beim Anlegen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final allPlayersAsync = ref.watch(
      _includeArchived
          ? allPlayersIncludingArchivedProvider
          : allActivePlayersProvider,
    );

    final candidates = membersAsync.maybeWhen(
      data: (members) {
        final memberIds = members.map((m) => m.id).toSet();
        return allPlayersAsync.maybeWhen(
          data: (allPlayers) =>
              allPlayers.where((p) => !memberIds.contains(p.id)).toList(),
          orElse: () => null,
        );
      },
      orElse: () => null,
    );

    return AlertDialog(
      title: const Text('Mitglied hinzufügen'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _includeArchived,
              onChanged: (value) =>
                  setState(() => _includeArchived = value ?? false),
              title: const Text('Archivierte Spieler einbeziehen'),
            ),
            if (candidates == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (candidates.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final player in candidates)
                      ListTile(
                        title: Text(player.name),
                        subtitle: player.archived
                            ? const Text('archiviert')
                            : null,
                        onTap: () => _addExisting(player.id),
                      ),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Keine weiteren bekannten Spieler verfügbar.'),
              ),
            const Divider(),
            TextField(
              controller: _newPlayerNameController,
              // Muss zur Players.name-Spaltenbegrenzung passen (siehe
              // players_table.dart, withLength(max: 60)).
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Oder neuen Spieler anlegen',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _createAndAdd,
                child: const Text('Anlegen & hinzufügen'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
