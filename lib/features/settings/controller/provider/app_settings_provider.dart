import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/app_settings.dart';
import '../settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// Hält die aktuellen AppSettings und kapselt das Schreiben in
/// SharedPreferences. Wird u. a. am Ende des Setup-Wizards aufgerufen.
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.read(settingsRepositoryProvider).load();
  }

  Future<void> setTrackOtherPlayersAndSelf({
    required bool trackOtherPlayers,
    required int selfPlayerId,
  }) async {
    final repo = ref.read(settingsRepositoryProvider);
    final updated = AppSettings(
      trackOtherPlayers: trackOtherPlayers,
      selfPlayerId: selfPlayerId,
    );
    await repo.save(updated);
    state = AsyncData(updated);
  }

  /// Ändert `trackOtherPlayers` NACH dem Setup-Wizard (z. B. über den
  /// Umschalter in der "Weitere Optionen"-Card auf dem Home-Screen) -
  /// im Unterschied zu [setTrackOtherPlayersAndSelf] bleibt der bereits
  /// vorhandene `selfPlayerId` unverändert. Rein additiv/nicht
  /// destruktiv: vorhandene Gruppen/Mitspieler-Daten bleiben in der
  /// Datenbank erhalten, nur die zugehörigen UI-Bereiche (Gruppen
  /// verwalten, Gruppen-/Teamauswahl bei Partien) werden je nach Wert
  /// ein-/ausgeblendet, siehe ARCHITECTURE.md.
  Future<void> setTrackOtherPlayers(bool trackOtherPlayers) async {
    final current = state.value;
    if (current == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    final updated = current.copyWith(trackOtherPlayers: trackOtherPlayers);
    await repo.save(updated);
    state = AsyncData(updated);
  }

  /// Schaltet das Wheel-of-Fortune-Feature global ein/aus (siehe
  /// AppSettings.wheelOfFortuneEnabled) - Umschalter auf dem
  /// Home-Screen, analog zu [setTrackOtherPlayers]. Rein additiv:
  /// bereits hinterlegte Aufgaben (AppSettings.wheelTasks) bleiben
  /// beim Ausschalten erhalten, nur der "Rad drehen"-Button in
  /// LiveGameScreen wird ausgeblendet.
  Future<void> setWheelOfFortuneEnabled(bool enabled) async {
    final current = state.value;
    if (current == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    final updated = current.copyWith(wheelOfFortuneEnabled: enabled);
    await repo.save(updated);
    state = AsyncData(updated);
  }

  /// Setzt die Aufgabe für GENAU eine WUBRG-Farbe auf der übergebenen
  /// Eskalations-Stufe (1-5, siehe AppSettings.wheelTasks/
  /// wheelTasksStage2/.../wheelTasksStage5) - die übrigen Farben UND
  /// die übrigen Stufen bleiben unverändert. Wird von WheelTasksScreen
  /// aufgerufen.
  Future<void> setWheelTask(
    String color,
    String taskText, {
    int stage = 1,
  }) async {
    final current = state.value;
    if (current == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    AppSettings updated;
    switch (stage) {
      case 2:
        final updatedTasks = Map<String, String>.from(current.wheelTasksStage2)
          ..[color] = taskText;
        updated = current.copyWith(wheelTasksStage2: updatedTasks);
        break;
      case 3:
        final updatedTasks = Map<String, String>.from(current.wheelTasksStage3)
          ..[color] = taskText;
        updated = current.copyWith(wheelTasksStage3: updatedTasks);
        break;
      case 4:
        final updatedTasks = Map<String, String>.from(current.wheelTasksStage4)
          ..[color] = taskText;
        updated = current.copyWith(wheelTasksStage4: updatedTasks);
        break;
      case 5:
        final updatedTasks = Map<String, String>.from(current.wheelTasksStage5)
          ..[color] = taskText;
        updated = current.copyWith(wheelTasksStage5: updatedTasks);
        break;
      default:
        final updatedTasks = Map<String, String>.from(current.wheelTasks)
          ..[color] = taskText;
        updated = current.copyWith(wheelTasks: updatedTasks);
    }
    await repo.save(updated);
    state = AsyncData(updated);
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
