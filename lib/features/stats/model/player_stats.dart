import '../../games/controller/repository/games_repository.dart';

/// Siegquote für ein einzelnes Deck (oder "Kein Deck angegeben"), Teil
/// von [PlayerStats.byDeck].
class DeckWinStats {
  final int? deckId;
  final String deckLabel;
  final String colorIdentity;
  final int gamesPlayed;
  final int wins;

  /// False, wenn dieses Deck laut Decks.ownerPlayerId einem ANDEREN
  /// Spieler gehoert (Deck-Verleih) - siehe
  /// SelfGameStatsRow.isOwnDeck. Ohne Deck-Angabe (deckId == null)
  /// true (siehe dort). Grundlage fuer die Aufteilung
  /// "Eigene Decks"/"Decks anderer" in stats_screen.dart
  /// (Nutzerwunsch).
  final bool isOwnDeck;

  const DeckWinStats({
    required this.deckId,
    required this.deckLabel,
    required this.colorIdentity,
    required this.gamesPlayed,
    required this.wins,
    required this.isOwnDeck,
  });

  /// null statt einer Division durch 0, wenn das Deck (noch) nie
  /// gespielt wurde - wird in der UI dann als "-" statt "0 %" angezeigt.
  double? get winRate => gamesPlayed == 0 ? null : wins / gamesPlayed;
}

/// Aggregierte Statistik-Kennzahlen für eine Menge von Partien-
/// Teilnahmen (siehe [computePlayerStats]) - erste Ausbaustufe des
/// Statistik-Dashboards: Siegquote gesamt und aufgeschlüsselt nach
/// Deck (mit dem Nutzer abgestimmt, siehe ARCHITECTURE.md).
class PlayerStats {
  final int gamesPlayed;
  final int wins;
  final List<DeckWinStats> byDeck;

  const PlayerStats({
    required this.gamesPlayed,
    required this.wins,
    required this.byDeck,
  });

  double? get winRate => gamesPlayed == 0 ? null : wins / gamesPlayed;

  static const empty = PlayerStats(gamesPlayed: 0, wins: 0, byDeck: []);
}

/// Berechnet [PlayerStats] aus einer (ggf. bereits nach Gruppe
/// gefilterten - siehe StatsScreen) Liste von Partien-Teilnahmen. Reine
/// Funktion ohne DB-Zugriff, analog zu game_setup_validator.dart, damit
/// die Aggregation unabhängig von der Datenquelle nachvollziehbar
/// bleibt. "Sieg" folgt derselben Definition wie überall sonst in der
/// App (GameParticipant.isWinner, aus placement == 1 abgeleitet) - bei
/// einem Unentschieden zählt das also für alle Teilnehmer als Sieg,
/// nicht separat ausgewiesen.
PlayerStats computePlayerStats(List<SelfGameStatsRow> rows) {
  final gamesPlayed = rows.length;
  final wins = rows.where((r) => r.isWinner).length;

  final byDeckId = <int?, List<SelfGameStatsRow>>{};
  for (final row in rows) {
    byDeckId.putIfAbsent(row.deckId, () => []).add(row);
  }

  final byDeck = [
    for (final entry in byDeckId.entries)
      DeckWinStats(
        deckId: entry.key,
        deckLabel: entry.value.first.deckName ?? 'Kein Deck angegeben',
        colorIdentity: entry.value.first.colorIdentity,
        gamesPlayed: entry.value.length,
        wins: entry.value.where((r) => r.isWinner).length,
        // Ownership eines Decks aendert sich nicht zwischen Partien -
        // der Wert der ersten Zeile dieses deckId-Buckets reicht.
        isOwnDeck: entry.value.first.isOwnDeck,
      ),
  ]..sort((a, b) => b.gamesPlayed.compareTo(a.gamesPlayed));

  return PlayerStats(gamesPlayed: gamesPlayed, wins: wins, byDeck: byDeck);
}
