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

  /// Mitgelieferte Vorbelegung der Wheel-of-Fortune-Aufgaben, thematisch
  /// über die 5 Eskalations-Stufen hinweg abgestuft (vom Nutzer als
  /// "Runde 1" bis "Runde 5" vorgegeben, jeweils sortiert nach
  /// Grün-Weiß-Blau-Rot-Schwarz). Frei überschreibbar über
  /// WheelTasksScreen - jede Stufe ist unabhängig überschreibbar, siehe
  /// _loadWheelTasks.
  static const Map<int, Map<String, String>> _defaultWheelTasksByStage = {
    1: {
      'G': 'Free Rampant Growth',
      'W': 'Ziehe eine Karte',
      'U': 'Jeder Spieler Scry 1',
      'R': 'Verliere drei Leben',
      'B': 'Wirf eine Karte ab',
    },
    2: {
      'G': 'Jeder zieht eine Karte',
      'W': 'Erzeuge zwei Treasures',
      'U': 'Free Counter Spell',
      'R': 'Opfere ein Permanent',
      'B': 'Verliere fünf Leben',
    },
    3: {
      'G': 'Free Generous Gift',
      'W': 'Ziehe Zwei Karten',
      'U': 'Jeder Spieler bekommt zwei Treasures',
      'R': 'Verschenke ein Permanent',
      'B': 'Verliere zehn Leben',
    },
    4: {
      'G': 'Erzeuge einen 8/8 Dino Token mit Trampeln und Eile',
      'W': "Teferi's Protection",
      'U': 'Jeder zieht zwei Karten',
      'R': 'Nur ein Spell diesen Turn',
      'B': 'Drei Permanente opfern',
    },
    5: {
      'G': 'Free Demonic Tutor',
      'W': 'Du kannst mit jemanden die Lebenspunkte tauschen',
      'U': 'Oberste Karte der Bibliothek spielen ohne Manakosten zu bezahlen',
      'R': 'Tausche deine Lebenspunkte mit dem Spieler, der die wenigsten hat',
      'B': 'Überspringe deinen eigenen Zug',
    },
  };

  /// Alte, bis vor Kurzem für ALLE 5 Stufen gemeinsam genutzte
  /// Platzhalter-Vorbelegung (vor der thematischen Ausdifferenzierung je
  /// Stufe). Wird nur noch als Erkennungsmerkmal gebraucht: Da [save]
  /// immer den kompletten [AppSettings]-Snapshot inklusive ALLER
  /// Aufgaben-Maps persistiert (nicht nur die eine gerade geänderte
  /// Farbe/Stufe), wurde dieser alte Platzhaltertext bei jedem noch so
  /// kleinen Settings-Update (z. B. Wheel of Fortune ein-/ausschalten)
  /// unbeabsichtigt fest unter dem jeweiligen SharedPreferences-
  /// Schlüssel "eingefroren", obwohl der Nutzer ihn nie bewusst gesetzt
  /// hatte. Ein gespeicherter Wert, der exakt diesem alten Text
  /// entspricht, wird deshalb beim Laden wie "nicht gesetzt" behandelt,
  /// damit die neuen, stufenspezifischen Default-Texte tatsächlich
  /// ankommen.
  static const Map<String, String> _legacySharedDefaults = {
    'W': 'Du erhältst ein Leben dazu',
    'U': 'Du hast nach deinem Zug einen weiteren Zug',
    'B': 'Jeder Spieler verliert ein Leben',
    'R': 'Füge jedem Gegner einen Schaden zu',
    'G': 'Jeder bekommt ein generisches Mana',
  };

  Map<String, String> _loadWheelTasks(SharedPreferences prefs, int stage) {
    final prefix = _wheelTaskPrefix(stage);
    final defaults = _defaultWheelTasksByStage[stage] ?? _defaultWheelTasksByStage[1]!;
    return {
      for (final entry in defaults.entries)
        entry.key: _resolveSavedTask(
          prefs.getString('$prefix${entry.key}'),
          entry.key,
          entry.value,
        ),
    };
  }

  /// Liefert den gespeicherten Aufgabentext - außer es ist keiner
  /// gespeichert (null) oder der gespeicherte Wert entspricht exakt dem
  /// alten, stufenübergreifend geteilten Platzhaltertext dieser Farbe
  /// (siehe [_legacySharedDefaults]); in beiden Fällen wird stattdessen
  /// der neue, stufenspezifische Default zurückgegeben.
  String _resolveSavedTask(String? saved, String color, String newDefault) {
    if (saved == null) return newDefault;
    if (saved == _legacySharedDefaults[color]) return newDefault;
    return saved;
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
