import 'package:flutter/material.dart';

import '../../../../core/utils/color_identity_utils.dart';
import '../../../../core/widgets/mana_symbol.dart';

/// Auswahl der Farbidentitaet eines Decks als Toggle-Chips: die 5
/// WUBRG-Farben plus ein zusaetzlicher "Farblos"-Chip (Nutzerwunsch:
/// beim Deck-Anlegen fehlte eine explizite neutrale/farblose Option -
/// technisch war das schon immer moeglich, indem man KEINE der 5
/// Farben auswaehlt (leerer String = farblos, siehe
/// core/utils/color_identity_utils.dart), das war aber nicht
/// entdeckbar/vorhanden als eigene Auswahl). [colorIdentity] ist der
/// normalisierte String (z. B. "WU", "" fuer farblos).
///
/// Zeigt zusaetzlich zum Farbnamen das echte Mana-Symbol
/// (siehe core/widgets/mana_symbol.dart) - Nutzerwunsch, angelehnt an
/// mtg_stats_tracker, wo dieselbe Auswahl bereits Mana-Symbole statt
/// nur Text nutzte. `showCheckmark: false`, damit das Symbol auch im
/// ausgewaehlten Zustand sichtbar bleibt statt vom Standard-
/// Material-Haekchen verdeckt zu werden - Auswahl wird stattdessen
/// (wie zuvor) ueber Chip-Hintergrund/-Rand angezeigt.
class ColorIdentityPicker extends StatelessWidget {
  final String colorIdentity;
  final ValueChanged<String> onChanged;

  const ColorIdentityPicker({
    super.key,
    required this.colorIdentity,
    required this.onChanged,
  });

  static const Map<String, String> _labels = {
    'W': 'Weiß',
    'U': 'Blau',
    'B': 'Schwarz',
    'R': 'Rot',
    'G': 'Grün',
  };

  @override
  Widget build(BuildContext context) {
    final selected = colorIdentity.split('').toSet();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // "Farblos" ist keine echte 6. WUBRG-Farbe, sondern nur die
        // Anzeige/Auswahl des Zustands "keine Farbe ausgewaehlt" - der
        // ManaSymbol-Fallback fuer eine unbekannte Farbe (hier: '')
        // liefert bereits das passende Colorless-Icon (ms_c), siehe
        // core/widgets/mana_symbol.dart. Erneutes Antippen im bereits
        // farblosen Zustand ist bewusst ein No-Op (bleibt farblos) -
        // "farblos" laesst sich nur durch Auswahl einer echten Farbe
        // verlassen, nicht durch Abwaehlen des Chips selbst.
        FilterChip(
          avatar: const ManaSymbol(color: '', size: 20),
          showCheckmark: false,
          label: const Text('Farblos'),
          selected: selected.isEmpty,
          onSelected: (_) => onChanged(''),
        ),
        for (final color in wubrgOrder)
          FilterChip(
            avatar: ManaSymbol(color: color, size: 20),
            showCheckmark: false,
            label: Text(_labels[color]!),
            selected: selected.contains(color),
            onSelected: (isSelected) {
              final updated = Set<String>.from(selected);
              if (isSelected) {
                updated.add(color);
              } else {
                updated.remove(color);
              }
              onChanged(normalizeColorIdentity(updated));
            },
          ),
      ],
    );
  }
}
