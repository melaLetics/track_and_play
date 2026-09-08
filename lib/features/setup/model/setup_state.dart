enum SetupStep { chooseMode, enterOwnName, createFirstGroup }

/// Lokaler (noch nicht persistierter) Zustand des Setup-Wizards.
/// Erst finishSetup() im SetupFlowController schreibt die Daten
/// tatsächlich in Players/Groups/AppSettings.
class SetupState {
  final SetupStep step;
  final bool trackOtherPlayers;
  final String ownName;
  final String firstGroupName;
  final bool isSaving;

  const SetupState({
    this.step = SetupStep.chooseMode,
    this.trackOtherPlayers = false,
    this.ownName = '',
    this.firstGroupName = '',
    this.isSaving = false,
  });

  SetupState copyWith({
    SetupStep? step,
    bool? trackOtherPlayers,
    String? ownName,
    String? firstGroupName,
    bool? isSaving,
  }) {
    return SetupState(
      step: step ?? this.step,
      trackOtherPlayers: trackOtherPlayers ?? this.trackOtherPlayers,
      ownName: ownName ?? this.ownName,
      firstGroupName: firstGroupName ?? this.firstGroupName,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}
