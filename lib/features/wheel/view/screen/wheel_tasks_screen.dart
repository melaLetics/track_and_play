import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/color_identity_names.dart';
import '../../../../core/utils/color_identity_utils.dart';
import '../../../../core/widgets/mana_symbol.dart';
import '../../../settings/controller/provider/app_settings_provider.dart';
import '../../../settings/model/app_settings.dart';
import '../widgets/wheel_task_editor_sheet.dart';

/// Verwaltung der Wheel-of-Fortune-Aufgaben (siehe
/// AppSettings.wheelTasks/wheelTasksStage2/.../wheelTasksStage5 sowie
/// WheelOfFortuneDialog) - EIN Eintrag je WUBRG-Farbe UND
/// Eskalations-Stufe (Nutzerwunsch: ursprünglich "drei Eskalations-
/// Stufen ... pro Stufe kann man pro Farbe eine neue Aufgabe
/// definieren", später auf "insgesamt fünf Eskalationsstufen"
/// erweitert), Reihenfolge der Farben wie überall sonst in der App
/// ([wubrgOrder]). Ein Reiter je Stufe (1-5), Antippen einer Farb-Karte
/// öffnet [WheelTaskEditorSheet]. Erreichbar sowohl über den
/// Bearbeiten-Button im Wheel-Overlay selbst als auch über "Weitere
/// Optionen" auf dem Home-Screen (siehe HomeScreen._QuickLinksCard,
/// nur sichtbar wenn AppSettings.wheelOfFortuneEnabled).
class WheelTasksScreen extends ConsumerWidget {
  const WheelTasksScreen({super.key});

  static const _stageCount = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);

    return DefaultTabController(
      length: _stageCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wheel of Fortune'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Stufe 1'),
              Tab(text: 'Stufe 2'),
              Tab(text: 'Stufe 3'),
              Tab(text: 'Stufe 4'),
              Tab(text: 'Stufe 5'),
            ],
          ),
        ),
        body: settingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text('Fehler beim Laden: $error', textAlign: TextAlign.center),
          ),
          data: (settings) => TabBarView(
            children: [
              for (var stage = 1; stage <= _stageCount; stage++)
                _StageTaskList(stage: stage, settings: settings, ref: ref),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aufgaben-Liste EINER Eskalations-Stufe - eigenes Widget statt
/// wiederholtem Inline-Code je Tab, damit alle Reiter identisch
/// aufgebaut sind und nur die Datenquelle (Stufe) variiert.
class _StageTaskList extends StatelessWidget {
  final int stage;
  final AppSettings settings;
  final WidgetRef ref;

  const _StageTaskList({
    required this.stage,
    required this.settings,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = settings.wheelTasksForStage(stage);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _introText,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        for (final color in wubrgOrder)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: ManaSymbol(color: color, size: 28),
              title: Text(colorIdentityNames[color] ?? color),
              subtitle: Text(tasks[color] ?? ''),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editTask(context, ref, color, tasks[color] ?? ''),
            ),
          ),
      ],
    );
  }

  /// Kurzbeschreibung je Stufe - bei den Zwischenstufen (2-4) jeweils
  /// mit dem konkreten Vielfachen der Mitspielerzahl, nach dem sie
  /// erreicht wird (siehe WheelOfFortuneDialog._stageForSpinNumber:
  /// Stufe N wird nach (N-1) x Mitspielerzahl Drehungen erreicht).
  String get _introText {
    switch (stage) {
      case 2:
        return 'Stufe 2 wird während einer Partie erreicht, sobald das '
            'Rad so oft gedreht wurde, wie Mitspieler teilnehmen - ab '
            'dann gelten diese (härteren/anderen) Aufgaben statt der von '
            'Stufe 1.';
      case 3:
        return 'Stufe 3 wird nach doppelt so vielen Drehungen wie '
            'Mitspieler teilnehmen erreicht.';
      case 4:
        return 'Stufe 4 wird nach dreifach so vielen Drehungen wie '
            'Mitspieler teilnehmen erreicht.';
      case 5:
        return 'Stufe 5 ist das Maximum: erreicht nach vierfach so '
            'vielen Drehungen wie Mitspieler teilnehmen. Ab hier bleiben '
            'die Aufgaben gleich, egal wie oft noch gedreht wird.';
      default:
        return 'Stufe 1 gilt zu Beginn jeder Partie. Jeder der 5 Farben '
            'ist eine Aufgabe zugeordnet, die nach dem Drehen des Rads '
            'angezeigt wird - jede Farbe kommt auf dem Rad zweimal vor, '
            'löst aber beide Male dieselbe hier hinterlegte Aufgabe aus. '
            'Die Aufgabe ist reiner Anzeigetext, den ihr selbst am Tisch '
            'umsetzt.';
    }
  }

  Future<void> _editTask(
    BuildContext context,
    WidgetRef ref,
    String color,
    String currentText,
  ) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => WheelTaskEditorSheet(
        color: color,
        initialText: currentText,
        stage: stage,
      ),
    );
    if (result == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .setWheelTask(color, result, stage: stage);
  }
}
