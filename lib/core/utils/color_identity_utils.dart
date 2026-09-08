/// Hilfsfunktionen rund um MTG-Farbidentitäten (WUBRG).
///
/// Eine Farbidentität wird intern immer als String aus den Buchstaben
/// W, U, B, R, G in dieser festen Reihenfolge gespeichert (z. B. "WU"),
/// unabhängig davon, in welcher Reihenfolge die Farben ausgewählt wurden.
/// Ein leerer String bedeutet farblos.
const List<String> wubrgOrder = ['W', 'U', 'B', 'R', 'G'];

String normalizeColorIdentity(Iterable<String> colors) {
  final set = colors.map((c) => c.toUpperCase()).toSet();
  return wubrgOrder.where(set.contains).join();
}
