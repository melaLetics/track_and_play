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
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
