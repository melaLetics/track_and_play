import '../../games/controller/repository/games_repository.dart';

/// Siegquote des Ich-Spielers für EIN eigenes, verliehenes Deck - Teil
/// von [LendingStats.byDeck]. Analog zu DeckWinStats (player_stats.dart),
/// aber aus der Gegenrichtung: nicht "wie schneide ich ab, wenn ICH
/// dieses Deck spiele", sondern "wie schneide ich ab, wenn ein GEGNER
/// dieses (mein) Deck spielt".
class LentDeckStats {
  final int deckId;
  final String deckLabel;
  final String colorIdentity;
  final int gamesPlayed;
  final int wins;

  const LentDeckStats({
    required this.deckId,
    required this.deckLabel,
    required this.colorIdentity,
    required this.gamesPlayed,
    required this.wins,
  });

  /// null statt einer Division durch 0, wenn dieses Deck (noch) nie
  /// verliehen wurde - wird in der UI dann als "-" statt "0 %" angezeigt.
  double? get winRate => gamesPlayed == 0 ? null : wins / gamesPlayed;
}

/// Aggregierte Auswertung "Wie schneide ich ab, wenn ein Gegner eines
/// meiner Decks spielt?" (Nutzerfrage "Gewinne ich gegen meine eigenen
/// Decks oder verliere ich eher?") - gesamt sowie aufgeschlüsselt je
/// verliehenem Deck. Siehe [computeLendingStats].
class LendingStats {
  final int gamesPlayed;
  final int wins;
  final List<LentDeckStats> byDeck;

  const LendingStats({
    required this.gamesPlayed,
    required this.wins,
    required this.byDeck,
  });

  double? get winRate => gamesPlayed == 0 ? null : wins / gamesPlayed;

  static const empty = LendingStats(gamesPlayed: 0, wins: 0, byDeck: []);
}

/// Berechnet [LendingStats] aus einer (ggf. bereits nach Gruppe
/// gefilterten - siehe StatsScreen) Liste von Partien-Teilnahmen des
/// Ich-Spielers. Reine Funktion ohne DB-Zugriff, analog zu
/// computePlayerStats (player_stats.dart).
///
/// Berücksichtigt werden nur Partien, in denen laut
/// [SelfGameStatsRow.lentDecks] mindestens ein EIGENES Deck von einem
/// ANDEREN Teilnehmer gespielt wurde (Deck-Verleih) - der Ich-Spieler
/// selbst hat in dieser Partie also zwangsläufig mitgespielt (sonst
/// gäbe es die Zeile gar nicht, siehe watchSelfGameStats), aber mit
/// einem BELIEBIGEN eigenen oder fremden Deck; entscheidend ist allein,
/// ob er diese eine Partie gewonnen hat (SelfGameStatsRow.isWinner,
/// bei Unentschieden für alle Teilnehmer true - dieselbe Definition
/// wie überall sonst in der App).
///
/// Verleiht der Ich-Spieler in EINER Partie mehrere eigene Decks
/// gleichzeitig an verschiedene Gegner, zählt diese Partie für die
/// Gesamt-Bilanz nur EINMAL, fließt aber in die Pro-Deck-Bilanz jedes
/// betroffenen Decks ein.
LendingStats computeLendingStats(List<SelfGameStatsRow> rows) {
  final relevantRows = [
    for (final row in rows)
      if (row.lentDecks.isNotEmpty) row,
  ];

  final gamesPlayed = relevantRows.length;
  final wins = relevantRows.where((r) => r.isWinner).length;

  final rowsByDeckId = <int, List<SelfGameStatsRow>>{};
  final infoByDeckId = <int, LentDeckInfo>{};
  for (final row in relevantRows) {
    for (final deck in row.lentDecks) {
      rowsByDeckId.putIfAbsent(deck.deckId, () => []).add(row);
      infoByDeckId.putIfAbsent(deck.deckId, () => deck);
    }
  }

  final byDeck = [
    for (final entry in rowsByDeckId.entries)
      LentDeckStats(
        deckId: entry.key,
        deckLabel: infoByDeckId[entry.key]!.deckName,
        colorIdentity: infoByDeckId[entry.key]!.colorIdentity,
        gamesPlayed: entry.value.length,
        wins: entry.value.where((r) => r.isWinner).length,
      ),
  ]..sort((a, b) => b.gamesPlayed.compareTo(a.gamesPlayed));

  return LendingStats(gamesPlayed: gamesPlayed, wins: wins, byDeck: byDeck);
}
