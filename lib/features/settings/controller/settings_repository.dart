import 'package:shared_preferences/shared_preferences.dart';

import '../model/app_settings.dart';

class SettingsRepository {
  static const _kTrackOtherPlayers = 'track_other_players';
  static const _kSelfPlayerId = 'self_player_id';
  static const _kWheelEnabled = 'wheel_of_fortune_enabled';

  /// Schlüssel-Präfix für die Wheel-of-Fortune-Aufgaben EINER
  /// Eskalations-Stufe (siehe AppSettings.wheelTasksForStage) - Stufe 1
  /// behält aus Kompatibilitätsgründen den historischen, unnummerierten
  /// Präfix ("wheel_task_") bei, damit bereits gespeicherte Stufe-1-
  /// Aufgaben aus der Zeit vor den weiteren Stufen unverändert erhalten
  /// bleiben. Stufen 2-5 nutzen "wheel_task_<stufe>_".
  static String _wheelTaskPrefix(int stage) =>
      stage <= 1 ? 'wheel_task_' : 'wheel_task_${stage}_';

  /// Mitgelieferte Vorbelegung der Wheel-of-Fortune-Aufgaben - 1:1 aus
  /// den Beispielen des Nutzers übernommen, damit das Feature sofort
  /// sinnvoll nutzbar ist, ohne dass erst alle 5 Farben manuell
  /// befüllt werden müssen. Frei überschreibbar über WheelTasksScreen.
  /// Gilt als Start-Vorbelegung für ALLE 5 Eskalations-Stufen
  /// gleichermaßen (siehe _loadWheelTasks) - jede Stufe ist danach
  /// unabhängig überschreibbar.
  static const Map<String, String> _defaultWheelTasks = {
    'W': 'Du erhältst ein Leben dazu',
    'U': 'Du hast nach deinem Zug einen weiteren Zug',
    'B': 'Jeder Spieler verliert ein Leben',
    'R': 'Füge jedem Gegner einen Schaden zu',
    'G': 'Jeder bekommt ein generisches Mana',
  };

  Map<String, String> _loadWheelTasks(SharedPreferences prefs, int stage) {
    final prefix = _wheelTaskPrefix(stage);
    return {
      for (final entry in _defaultWheelTasks.entries)
        entry.key: prefs.getString('$prefix${entry.key}') ?? entry.value,
    };
  }

  Future<void> _saveWheelTasks(
    SharedPreferences prefs,
    int stage,
    Map<String, String> tasks,
  ) async {
    final prefix = _wheelTaskPrefix(stage);
    for (final entry in tasks.entries) {
      await prefs.setString('$prefix${entry.key}', entry.value);
    }
  }

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      trackOtherPlayers: prefs.getBool(_kTrackOtherPlayers) ?? false,
      selfPlayerId: prefs.getInt(_kSelfPlayerId),
      wheelOfFortuneEnabled: prefs.getBool(_kWheelEnabled) ?? false,
      wheelTasks: _loadWheelTasks(prefs, 1),
      wheelTasksStage2: _loadWheelTasks(prefs, 2),
      wheelTasksStage3: _loadWheelTasks(prefs, 3),
      wheelTasksStage4: _loadWheelTasks(prefs, 4),
      wheelTasksStage5: _loadWheelTasks(prefs, 5),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrackOtherPlayers, settings.trackOtherPlayers);
    final selfId = settings.selfPlayerId;
    if (selfId != null) {
      await prefs.setInt(_kSelfPlayerId, selfId);
    }
    await prefs.setBool(_kWheelEnabled, settings.wheelOfFortuneEnabled);
    await _saveWheelTasks(prefs, 1, settings.wheelTasks);
    await _saveWheelTasks(prefs, 2, settings.wheelTasksStage2);
    await _saveWheelTasks(prefs, 3, settings.wheelTasksStage3);
    await _saveWheelTasks(prefs, 4, settings.wheelTasksStage4);
    await _saveWheelTasks(prefs, 5, settings.wheelTasksStage5);
  }
}
