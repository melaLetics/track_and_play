/// Globale App-Einstellungen.
///
/// [trackOtherPlayers] = false: Es wird nur der Nutzer selbst als
/// Spieler (inkl. eigener Decks) dauerhaft erfasst - reiner
/// Solo-Betrieb, keine Gruppen, keine Mitspieler-Verwaltung.
///
/// [trackOtherPlayers] = true: Zusätzlich können beliebig viele
/// Spielgruppen mit eigenen Mitgliedern und deren Decks angelegt und
/// verwaltet werden (siehe Groups/PlayerGroupMemberships).
///
/// Unabhängig von diesem Schalter können jederzeit Partien mit
/// unbekannten Spielern/Decks (nur Farbidentität) erfasst werden -
/// siehe GameParticipants.
class AppSettings {
  final bool trackOtherPlayers;
  final int? selfPlayerId;

  /// Ob das optionale "Wheel of Fortune"-Gamification-Feature im
  /// Live-Tracking verfügbar ist (Nutzerwunsch: soll genau wie
  /// [trackOtherPlayers] ein globaler Ein-/Aus-Schalter sein, siehe
  /// HomeScreen). Nur wenn true, zeigt LiveGameScreen den
  /// "Rad drehen"-Button.
  final bool wheelOfFortuneEnabled;

  /// Die dem Rad zugeordneten Aufgaben, je EIN Satz Texte pro
  /// Eskalations-Stufe (1-5, siehe unten) - Schlüssel wie überall sonst
  /// in der App ein einzelner Großbuchstabe (siehe wubrgOrder/
  /// manaColors in core/utils/). [wheelTasks] ist Stufe 1 (Startwert,
  /// Feldname aus Kompatibilitätsgründen unverändert gelassen).
  /// Jede der 5 Farben hat je Stufe IMMER einen Eintrag (siehe
  /// SettingsRepository für die mitgelieferten Vorbelegungen, 1:1 aus
  /// den Beispielen des Nutzers übernommen) - vollständig in
  /// WheelTasksScreen vom Nutzer überschreibbar. Jede Farbe kommt auf
  /// dem Rad selbst zweimal vor (siehe WheelOfFortuneDialog), löst aber
  /// beide Male dieselbe hier hinterlegte Aufgabe der jeweils aktuellen
  /// Stufe aus.
  final Map<String, String> wheelTasks;

  /// Aufgaben für Eskalations-Stufe 2 (Nutzerwunsch: ursprünglich "drei
  /// Eskalationsstufen ... pro Stufe kann man pro Farbe eine neue
  /// Aufgabe definieren", später auf 5 Stufen erweitert). Wird
  /// erreicht, sobald in einer Partie so oft gedreht wurde, wie
  /// Mitspieler teilnehmen (siehe
  /// WheelOfFortuneDialog._stageForSpinNumber).
  final Map<String, String> wheelTasksStage2;

  /// Aufgaben für Eskalations-Stufe 3 - erreicht nach doppelt so vielen
  /// Drehungen wie Mitspieler teilnehmen.
  final Map<String, String> wheelTasksStage3;

  /// Aufgaben für Eskalations-Stufe 4 - erreicht nach dreifach so
  /// vielen Drehungen wie Mitspieler teilnehmen.
  final Map<String, String> wheelTasksStage4;

  /// Aufgaben für Eskalations-Stufe 5 - Maximum (Nutzerwunsch: "auf
  /// insgesamt fünf Eskalationsstufen erweitern"), erreicht nach
  /// vierfach so vielen Drehungen wie Mitspieler teilnehmen. Ab hier
  /// bleiben die Aufgaben unabhängig von weiteren Drehungen gleich.
  final Map<String, String> wheelTasksStage5;

  const AppSettings({
    this.trackOtherPlayers = false,
    this.selfPlayerId,
    this.wheelOfFortuneEnabled = false,
    this.wheelTasks = const {},
    this.wheelTasksStage2 = const {},
    this.wheelTasksStage3 = const {},
    this.wheelTasksStage4 = const {},
    this.wheelTasksStage5 = const {},
  });

  /// Liefert die Aufgaben-Map der übergebenen Eskalations-Stufe (1-5) -
  /// Werte außerhalb dieses Bereichs fallen auf Stufe 1 zurück. Von
  /// WheelOfFortuneDialog genutzt, um je nach aktueller Stufe die
  /// passenden Texte nachzuschlagen.
  Map<String, String> wheelTasksForStage(int stage) {
    switch (stage) {
      case 2:
        return wheelTasksStage2;
      case 3:
        return wheelTasksStage3;
      case 4:
        return wheelTasksStage4;
      case 5:
        return wheelTasksStage5;
      default:
        return wheelTasks;
    }
  }

  AppSettings copyWith({
    bool? trackOtherPlayers,
    int? selfPlayerId,
    bool? wheelOfFortuneEnabled,
    Map<String, String>? wheelTasks,
    Map<String, String>? wheelTasksStage2,
    Map<String, String>? wheelTasksStage3,
    Map<String, String>? wheelTasksStage4,
    Map<String, String>? wheelTasksStage5,
  }) {
    return AppSettings(
      trackOtherPlayers: trackOtherPlayers ?? this.trackOtherPlayers,
      selfPlayerId: selfPlayerId ?? this.selfPlayerId,
      wheelOfFortuneEnabled:
          wheelOfFortuneEnabled ?? this.wheelOfFortuneEnabled,
      wheelTasks: wheelTasks ?? this.wheelTasks,
      wheelTasksStage2: wheelTasksStage2 ?? this.wheelTasksStage2,
      wheelTasksStage3: wheelTasksStage3 ?? this.wheelTasksStage3,
      wheelTasksStage4: wheelTasksStage4 ?? this.wheelTasksStage4,
      wheelTasksStage5: wheelTasksStage5 ?? this.wheelTasksStage5,
    );
  }
}
