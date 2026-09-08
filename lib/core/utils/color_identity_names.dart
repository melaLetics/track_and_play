/// Uebersetzt eine normierte WUBRG-Farbidentitaet (siehe
/// color_identity_utils.dart, normalizeColorIdentity) in die
/// zugehoerige Gilden-/Keil-/Kombinations-Bezeichnung (z. B. "UBR" ->
/// "Grixis") - Nutzerwunsch, angelehnt an mtg_stats_tracker (dort
/// MtgColorIdentity-Enum in color_identity.dart). Die Gilden-/Keil-
/// Namen sind offizielle, im Deutschen ebenfalls unuebersetzte Magic-
/// Begriffe (Grixis bleibt Grixis) - nur die einfarbigen und die
/// fuenffarbige Bezeichnung sind hier bewusst auf Deutsch, passend zum
/// Rest der App (Einfarbig nutzt dieselben Namen wie
/// ColorIdentityPicker._labels).
const Map<String, String> colorIdentityNames = {
  '': 'Farblos',

  // Einfarbig
  'W': 'Weiß',
  'U': 'Blau',
  'B': 'Schwarz',
  'R': 'Rot',
  'G': 'Grün',

  // Gilden (2-farbig)
  'WU': 'Azorius',
  'UB': 'Dimir',
  'BR': 'Rakdos',
  'RG': 'Gruul',
  'WG': 'Selesnya',
  'WB': 'Orzhov',
  'UR': 'Izzet',
  'BG': 'Golgari',
  'WR': 'Boros',
  'UG': 'Simic',

  // Shards (3-farbig, verbuendete Farben)
  'WUG': 'Bant',
  'WUB': 'Esper',
  'UBR': 'Grixis',
  'BRG': 'Jund',
  'WRG': 'Naya',

  // Keile/Wedges (3-farbig, gegnerische Farben)
  'WBG': 'Abzan',
  'WUR': 'Jeskai',
  'UBG': 'Sultai',
  'WBR': 'Mardu',
  'URG': 'Temur',

  // 4-farbig (benannt nach der fehlenden Farbe)
  'UBRG': 'Glint',
  'WBRG': 'Dune',
  'WURG': 'Ink',
  'WUBG': 'Witch',
  'WUBR': 'Yore',

  // 5-farbig
  'WUBRG': 'Fünffarbig',
};

/// Anzeigename einer normierten Farbidentitaet - bekannte Kombination
/// (siehe [colorIdentityNames]) liefert den Gilden-/Keil-Namen, alles
/// andere (z. B. ein zukuenftig unerwarteter String) faellt auf den
/// rohen String selbst zurueck statt eine Ausnahme zu werfen.
String colorIdentityDisplayName(String colorIdentity) =>
    colorIdentityNames[colorIdentity] ?? colorIdentity;
