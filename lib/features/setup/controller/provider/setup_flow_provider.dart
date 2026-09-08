import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/setup_state.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import '../../../groups/controller/provider/groups_repository_provider.dart';
import '../../../settings/controller/provider/app_settings_provider.dart';

class SetupFlowController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  void setTrackOtherPlayers(bool value) {
    state = state.copyWith(
      trackOtherPlayers: value,
      step: SetupStep.enterOwnName,
    );
  }

  void setOwnName(String name) {
    state = state.copyWith(ownName: name);
  }

  void goToCreateFirstGroup() {
    state = state.copyWith(step: SetupStep.createFirstGroup);
  }

  void setFirstGroupName(String name) {
    state = state.copyWith(firstGroupName: name);
  }

  /// Schließt den Wizard ab: legt den Self-Player an, speichert die
  /// Einstellung und - falls angegeben - die erste Gruppe (inkl.
  /// Mitgliedschaft des Self-Players darin).
  ///
  /// Fehler (z. B. eine verletzte Datenbank-Constraint) werden NICHT
  /// hier abgefangen, sondern an den Aufrufer (SetupWizard) weiter-
  /// gereicht, der sie als SnackBar anzeigen kann - isSaving wird aber
  /// in jedem Fall (auch bei einem Fehler) im finally-Block wieder
  /// zurückgesetzt, damit die UI nicht dauerhaft im Lade-Zustand
  /// hängen bleibt.
  Future<void> finishSetup() async {
    state = state.copyWith(isSaving: true);
    try {
      final playersRepo = ref.read(playersRepositoryProvider);
      final selfId = await playersRepo.createSelf(state.ownName.trim());

      await ref
          .read(settingsControllerProvider.notifier)
          .setTrackOtherPlayersAndSelf(
            trackOtherPlayers: state.trackOtherPlayers,
            selfPlayerId: selfId,
          );

      final groupName = state.firstGroupName.trim();
      if (state.trackOtherPlayers && groupName.isNotEmpty) {
        final groupsRepo = ref.read(groupsRepositoryProvider);
        final groupId = await groupsRepo.createGroup(groupName);
        await groupsRepo.addMember(groupId, selfId);
      }

      // AppRoot beobachtet selfPlayerProvider, um zwischen Setup-Wizard
      // und Hauptansicht zu unterscheiden - nach dem Anlegen neu laden.
      ref.invalidate(selfPlayerProvider);
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }
}

final setupFlowProvider =
    NotifierProvider<SetupFlowController, SetupState>(SetupFlowController.new);
