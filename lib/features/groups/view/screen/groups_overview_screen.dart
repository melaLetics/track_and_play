import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../controller/provider/groups_repository_provider.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import 'group_detail_screen.dart';

/// Übersicht der Spielgruppen. Der "Archivierte anzeigen"-Umschalter
/// (siehe ARCHITECTURE.md, Nutzeranforderung "Wie sehe ich archivierte
/// Daten?") blendet zusätzlich archivierte Gruppen ein, sonst waren
/// diese nach dem Archivieren nirgends mehr sichtbar/reaktivierbar.
class GroupsOverviewScreen extends ConsumerStatefulWidget {
  const GroupsOverviewScreen({super.key});

  @override
  ConsumerState<GroupsOverviewScreen> createState() =>
      _GroupsOverviewScreenState();
}

class _GroupsOverviewScreenState extends ConsumerState<GroupsOverviewScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(
      _showArchived ? allGroupsIncludingArchivedProvider : allGroupsProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spielgruppen'),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.archive : Icons.archive_outlined),
            tooltip: _showArchived
                ? 'Archivierte Gruppen ausblenden'
                : 'Archivierte Gruppen anzeigen',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Spielgruppe angelegt.\n'
                  'Tippe unten rechts auf "+", um deine erste Gruppe zu '
                  'erstellen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) => _GroupListTile(group: groups[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'groups_overview_fab',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _CreateGroupDialog(),
        ),
        tooltip: 'Neue Gruppe',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Dialog zum Anlegen einer neuen Spielgruppe. Als eigenes
/// ConsumerStatefulWidget umgesetzt, damit der TextEditingController
/// korrekt über initState/dispose verwaltet wird - siehe
/// core/widgets/rename_dialog.dart für die ausführliche Begründung, warum
/// ein manuell nach einem awaited showDialog()-Aufruf disposter Controller
/// zu "TextEditingController was used after being disposed" (und in der
/// Folge zu einer kaskadierenden "_dependents.isEmpty"-Assertion) führt.
class _CreateGroupDialog extends ConsumerStatefulWidget {
  const _CreateGroupDialog();

  @override
  ConsumerState<_CreateGroupDialog> createState() =>
      _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<_CreateGroupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final selfPlayerFuture = ref.read(selfPlayerProvider.future);
    final groupsRepo = ref.read(groupsRepositoryProvider);
    // Dialog sofort schliessen, danach erst anlegen - siehe Begründung
    // oben (rename_dialog.dart).
    Navigator.of(context).pop();
    try {
      final selfPlayer = await selfPlayerFuture;
      if (selfPlayer != null) {
        await groupsRepo.createGroupWithMember(name, selfPlayer.id);
      } else {
        await groupsRepo.createGroup(name);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler beim Anlegen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neue Spielgruppe'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        // Muss zur Groups.name-Spaltenbegrenzung passen (siehe
        // groups_table.dart, withLength(max: 60)).
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Gruppenname'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _create,
          child: const Text('Anlegen'),
        ),
      ],
    );
  }
}

class _GroupListTile extends ConsumerWidget {
  final Group group;

  const _GroupListTile({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCountAsync = ref.watch(groupMemberCountProvider(group.id));

    return Opacity(
      opacity: group.archived ? 0.6 : 1,
      child: ListTile(
        leading: const Icon(Icons.groups),
        title: Text(group.name),
        subtitle: memberCountAsync.when(
          loading: () => const Text('...'),
          error: (_, __) => const Text('? Mitglieder'),
          data: (count) => Text(
            '$count Mitglied${count == 1 ? '' : 'er'}'
            '${group.archived ? ' · archiviert' : ''}',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GroupDetailScreen(groupId: group.id),
            ),
          );
        },
      ),
    );
  }
}
