/// Wem eine Wheel-of-Fortune-Aufgabe (siehe AppSettings.wheelTasks)
/// nützt bzw. schadet - rein beschreibend fürs Vorschlags-Chip-Label
/// (siehe [wheelTaskSuggestions]), hat keine Auswirkung auf die
/// eigentliche Spiellogik (die Aufgabe ist reiner Anzeigetext, den die
/// Spieler selbst manuell umsetzen, siehe WheelOfFortuneDialog).
enum WheelTaskScope { all, opponents, self }

extension WheelTaskScopeLabel on WheelTaskScope {
  String get label => switch (this) {
        WheelTaskScope.all => 'alle',
        WheelTaskScope.opponents => 'Gegner',
        WheelTaskScope.self => 'du',
      };
}

/// Ein vorgeschlagener Aufgabentext für den Wheel-of-Fortune-
/// Aufgaben-Editor (siehe WheelTaskEditorSheet) - Nutzerwunsch: "ein
/// paar Optionen vorschlagen (die sowohl positiv als auch negativ
/// sind; alle, nur die Gegner oder nur sich selbst betreffen)". Rein
/// als Tipp-Hilfe gedacht - antippen übernimmt [text] in das
/// Textfeld, das Ergebnis bleibt danach frei weiter editierbar.
class WheelTaskSuggestion {
  final String chipLabel;
  final String text;
  final bool positive;
  final WheelTaskScope scope;

  const WheelTaskSuggestion({
    required this.chipLabel,
    required this.text,
    required this.positive,
    required this.scope,
  });
}

/// Deckt bewusst alle 6 Kombinationen aus Polarität (positiv/negativ)
/// und Reichweite (alle/Gegner/du) mit je 2 Beispielen ab, angelehnt
/// an die vom Nutzer selbst genannten Beispiele (Schaden an Gegner,
/// generisches Mana für alle, Leben für dich, Extra-Zug, Lebensverlust
/// für alle).
const List<WheelTaskSuggestion> wheelTaskSuggestions = [
  WheelTaskSuggestion(
    chipLabel: 'Leben +1 (du)',
    text: 'Du erhältst ein Leben dazu',
    positive: true,
    scope: WheelTaskScope.self,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Extra-Zug (du)',
    text: 'Du hast nach deinem Zug einen weiteren Zug',
    positive: true,
    scope: WheelTaskScope.self,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Karte ziehen (du)',
    text: 'Ziehe eine Karte',
    positive: true,
    scope: WheelTaskScope.self,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Mana für alle',
    text: 'Jeder Spieler erhält ein generisches Mana',
    positive: true,
    scope: WheelTaskScope.all,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Alle ziehen',
    text: 'Jeder Spieler darf eine Karte ziehen',
    positive: true,
    scope: WheelTaskScope.all,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Leben +1 (Gegner)',
    text: 'Ein zufällig gewählter Gegner erhält ein Leben dazu',
    positive: true,
    scope: WheelTaskScope.opponents,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Schaden (Gegner)',
    text: 'Füge jedem Gegner einen Schaden zu',
    positive: false,
    scope: WheelTaskScope.opponents,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Leben -1 (Gegner)',
    text: 'Jeder Gegner verliert ein Leben',
    positive: false,
    scope: WheelTaskScope.opponents,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Leben -1 (alle)',
    text: 'Jeder Spieler verliert ein Leben',
    positive: false,
    scope: WheelTaskScope.all,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Abwerfen (alle)',
    text: 'Jeder Spieler legt eine Handkarte ab',
    positive: false,
    scope: WheelTaskScope.all,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Leben -1 (du)',
    text: 'Du verlierst ein Leben',
    positive: false,
    scope: WheelTaskScope.self,
  ),
  WheelTaskSuggestion(
    chipLabel: 'Abwerfen (du)',
    text: 'Du legst eine Handkarte ab',
    positive: false,
    scope: WheelTaskScope.self,
  ),
];
