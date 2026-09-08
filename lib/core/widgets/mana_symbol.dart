import 'package:flutter/material.dart';
import 'package:mana_icons_flutter/mana_icons_flutter.dart';

import '../utils/mana_colors.dart';

/// Farbiges Mana-Symbol (echte Magic-Glyphe statt reinem Buchstaben)
/// fuer eine WUBRG-Farbe - Nutzerwunsch, angelehnt an
/// mtg_stats_tracker (dort `DeckColorIcon`, allerdings mit vollen
/// Farbnamen statt der hier durchgaengig genutzten Buchstaben, siehe
/// core/utils/color_identity_utils.dart). Nutzt das Paket
/// `mana_icons_flutter`, das bereits als ungenutzte Abhaengigkeit in
/// pubspec.yaml vorhanden war (vermutlich beim Projekt-Setup 1:1 aus
/// mtg_stats_tracker uebernommen, aber bislang nirgends verwendet).
///
/// [color] ist ein einzelner WUBRG-Buchstabe ('W'/'U'/'B'/'R'/'G');
/// alles andere (z. B. '' fuer farblos) zeigt das Colorless-Symbol.
/// Der Kreis-Hintergrund ist bewusst NICHT von den Vault & Foil-
/// Theme-Farben abhaengig (wie `manaIconBackgroundColor` im
/// Vorgaenger) - die Mana-Farben (siehe mana_colors.dart) sollen in
/// hellem wie dunklem Modus gleich gut erkennbar bleiben, statt mit
/// dem Vault- oder Parchment-Hintergrund zu verschmelzen. Ausnahme:
/// Weiss (Nutzer-Feedback - das helle Symbol war auf dem hellen
/// Standard-Hintergrund kaum zu erkennen) bekommt einen eigenen
/// dunklen Hintergrund (siehe [_backgroundFor]), alle anderen Farben
/// bleiben beim neutralen hellen Hintergrund.
class ManaSymbol extends StatelessWidget {
  final String color;
  final double size;

  const ManaSymbol({super.key, required this.color, this.size = 22});

  static const Map<String, IconData> _icons = {
    'W': ManaIcons.ms_w,
    'U': ManaIcons.ms_u,
    'B': ManaIcons.ms_b,
    'R': ManaIcons.ms_r,
    'G': ManaIcons.ms_g,
  };

  static const Color _coinColor = Color(0xFFD8CFC9);

  // Nur fuer Weiss: dunkler Hintergrund statt des neutralen hellen
  // _coinColor, sonst verschwindet das helle Symbol darauf (siehe
  // Klassendoku).
  static const Color _darkCoinColor = Color(0xFF2A2622);

  Color _backgroundFor(String color) =>
      color == 'W' ? _darkCoinColor : _coinColor;

  @override
  Widget build(BuildContext context) {
    final icon = _icons[color] ?? ManaIcons.ms_c;
    final tint = manaColors[color] ?? colorlessManaColor;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _backgroundFor(color),
        border: const Border.fromBorderSide(
          BorderSide(color: Colors.black26, width: 1),
        ),
      ),
      child: Icon(icon, color: tint, size: size * 0.62),
    );
  }
}

/// Reihe von [ManaSymbol]s fuer eine komplette Farbidentitaet (z. B.
/// "WU" -> Weiss- und Blau-Symbol nebeneinander) - fuer Stellen, an
/// denen bislang nur der rohe WUBRG-String angezeigt wurde (Nutzer-
/// wunsch, siehe ARCHITECTURE.md "Bekannte Fixes"). Leerer String
/// zeigt ein einzelnes farbloses Symbol.
class ManaSymbolRow extends StatelessWidget {
  final String colorIdentity;
  final double size;
  final double spacing;

  const ManaSymbolRow({
    super.key,
    required this.colorIdentity,
    this.size = 16,
    this.spacing = 2,
  });

  @override
  Widget build(BuildContext context) {
    final letters = colorIdentity.isEmpty ? [''] : colorIdentity.split('');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < letters.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          ManaSymbol(color: letters[i], size: size),
        ],
      ],
    );
  }
}
