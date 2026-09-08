import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/provider/setup_flow_provider.dart';
import '../../model/setup_state.dart';

/// Einmaliger Ersteinrichtungs-Dialog: legt den "Ich"-Spieler an,
/// entscheidet zwischen Solo-Betrieb und Verwaltung weiterer
/// Spieler/Gruppen, und erlaubt optional das direkte Anlegen der
/// ersten Spielgruppe.
class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  final _nameController = TextEditingController();
  final _groupNameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  /// Ruft finishSetup() auf und zeigt einen etwaigen Fehler (z. B. ein
  /// unerwartetes Speicherproblem) als SnackBar an, statt ihn
  /// unbehandelt verpuffen zu lassen. finishSetup() selbst setzt
  /// isSaving in jedem Fall (auch bei Fehlern) wieder zurück.
  Future<void> _finishSetup(SetupFlowController controller) async {
    try {
      await controller.finishSetup();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupFlowProvider);
    final controller = ref.read(setupFlowProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Willkommen bei Track & Play', style: TextStyle(fontSize: 23,),),),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (state.step) {
          SetupStep.chooseMode => _ChooseModeStep(
              onSelected: controller.setTrackOtherPlayers,
            ),
          SetupStep.enterOwnName => _EnterNameStep(
              controller: _nameController,
              trackOtherPlayers: state.trackOtherPlayers,
              onContinue: () {
                controller.setOwnName(_nameController.text);
                if (state.trackOtherPlayers) {
                  controller.goToCreateFirstGroup();
                } else {
                  _finishSetup(controller);
                }
              },
            ),
          SetupStep.createFirstGroup => _CreateFirstGroupStep(
              controller: _groupNameController,
              isSaving: state.isSaving,
              onFinish: () {
                controller.setFirstGroupName(_groupNameController.text);
                _finishSetup(controller);
              },
            ),
        },
      ),
    );
  }
}

class _ChooseModeStep extends StatelessWidget {
  final ValueChanged<bool> onSelected;

  const _ChooseModeStep({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Möchtest du nur deine eigenen Partien erfassen, oder auch '
          'Mitspieler und Spielgruppen verwalten?',
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => onSelected(false),
          child: const Text('Nur ich selbst'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => onSelected(true),
          child: const Text('Auch Mitspieler / Gruppen'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Das lässt sich später jederzeit in den Einstellungen ändern.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _EnterNameStep extends StatelessWidget {
  final TextEditingController controller;
  final bool trackOtherPlayers;
  final VoidCallback onContinue;

  const _EnterNameStep({
    required this.controller,
    required this.trackOtherPlayers,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Wie sollen wir dich nennen?', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          autofocus: true,
          // Muss zur Players.name-Spaltenbegrenzung passen (siehe
          // players_table.dart, withLength(min: 1, max: 60)) - sonst
          // schlägt das Speichern ohne UI-Feedback fehl.
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Dein Name'),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 24),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            return FilledButton(
              onPressed: value.text.trim().isEmpty ? null : onContinue,
              child: Text(trackOtherPlayers ? 'Weiter' : 'Fertig'),
            );
          },
        ),
      ],
    );
  }
}

class _CreateFirstGroupStep extends StatelessWidget {
  final TextEditingController controller;
  final bool isSaving;
  final VoidCallback onFinish;

  const _CreateFirstGroupStep({
    required this.controller,
    required this.isSaving,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Möchtest du direkt deine erste Spielgruppe anlegen '
          '(z. B. "Freitagsrunde")? Das geht auch jederzeit später.',
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          autofocus: true,
          // Muss zur Groups.name-Spaltenbegrenzung passen (siehe
          // groups_table.dart, withLength(min: 1, max: 60)).
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Gruppenname (optional)'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: isSaving ? null : onFinish,
          child: isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Fertig'),
        ),
      ],
    );
  }
}
