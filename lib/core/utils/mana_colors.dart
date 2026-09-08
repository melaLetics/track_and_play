import 'package:flutter/material.dart';

/// Mana-Farben (WUBRG) fuer den Kartenstapel-Look eines Decks (siehe
/// deck_stack_card.dart) - bewusst an den physischen Magic-Kartenfarben
/// orientiert statt an der App-Akzentfarbe (Vault & Foil), damit die
/// "Karten" farblich sofort als Weiss/Blau/Schwarz/Rot/Gruen erkennbar
/// sind. Reihenfolge und Buchstaben entsprechen
/// core/utils/color_identity_utils.dart (wubrgOrder).
const Map<String, Color> manaColors = {
  'W': Color(0xFFF7F1DD),
  'U': Color(0xFF2196F3),
  'B': Color(0xFF4A4A4A),
  'R': Color(0xFFE53935),
  'G': Color(0xFF43A047),
};

/// Grauton fuer farblose Decks (kein Eintrag in [colorIdentity]).
const Color colorlessManaColor = Color(0xFFB9B9B9);

/// Liefert die Kartenfarbe(n) einer Farbidentitaet (z. B. "WU" ->
/// [manaColors['W'], manaColors['U']]) fuer Gradient-Aufbau im
/// Kartenstapel; bei farblosen Decks eine einzelne Grau-"Farbe".
List<Color> manaColorsFor(String colorIdentity) {
  if (colorIdentity.isEmpty) return const [colorlessManaColor];
  return [
    for (final c in colorIdentity.split(''))
      manaColors[c] ?? colorlessManaColor,
  ];
}
