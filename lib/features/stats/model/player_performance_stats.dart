import 'dart:math' as math;

import '../../games/controller/repository/games_repository.dart';

/// Siegquote für eine benannte Gruppe von Partien-Teilnahmen (z. B. ein
/// Startpositions-Terzil, ein Dauer-Terzil oder eine Farbidentität).
/// Bewusst generisch statt drei fast identischer Klassen, siehe
/// [computeWinRateByStartPosition], [computeWinRateByDuration] und
/// [computeWinRateByColorIdentity].
class BucketWinStats {
  final String label;
  final int gamesPlayed;
  final int wins;

  const BucketWinStats({
    required this.label,
    required this.gamesPlayed,
    required this.wins,
  });

  double? get winRate => gamesPlayed == 0 ? null : wins / gamesPlayed;
}

/// Ordnet jede Partie anhand der NORMIERTEN Startposition des
/// Ich-Spielers (0 = zuerst am Zug, 1 = zuletzt) einem von drei
/// gleich breiten Terzilen zu (Früh/Mittel/Spät). Normiert auf
/// participantCount, damit z. B. Platz 2 von 4 und Platz 3 von 6
/// (beide "relativ früh") vergleichbar in denselben Topf fallen.
/// Partien ohne erfasste Startposition (z. B. manuell nachgetragen)
/// oder mit nur einem Teilnehmer werden ausgelassen.
List<BucketWinStats> computeWinRateByStartPosition(
  List<SelfGameStatsRow> rows,
) {
  const labels = ['Früh', 'Mittel', 'Spät'];
  final buckets = {for (final l in labels) l: <SelfGameStatsRow>[]};

  for (final r in rows) {
    if (r.startPosition == null || r.participantCount <= 1) continue;
    final relative = (r.startPosition! - 1) / (r.participantCount - 1);
    final label = relative <= 1 / 3
        ? 'Früh'
        : (relative <= 2 / 3 ? 'Mittel' : 'Spät');
    buckets[label]!.add(r);
  }

  return [
    for (final l in labels)
      BucketWinStats(
        label: l,
        gamesPlayed: buckets[l]!.length,
        wins: buckets[l]!.where((r) => r.isWinner).length,
      ),
  ];
}

/// Teilt die Partien mit erfasster Dauer (nur Live-Erfassung, siehe
/// Games.durationSeconds) in drei etwa gleich große Gruppen (Terzile
/// der eigenen Partiendauern) ein - bewusst KEINE festen
/// Minutenschwellen, da "lang" stark vom Modus und der Spielrunde
/// abhängt. Bei weniger als drei Partien mit Dauer ist eine sinnvolle
/// Dreiteilung nicht möglich; es wird dann eine leere Liste
/// zurückgegeben (UI zeigt in diesem Fall einen Hinweis).
List<BucketWinStats> computeWinRateByDuration(List<SelfGameStatsRow> rows) {
  final withDuration = rows.where((r) => r.durationSeconds != null).toList()
    ..sort((a, b) => a.durationSeconds!.compareTo(b.durationSeconds!));
  if (withDuration.length < 3) return [];

  const labels = ['Kurz', 'Mittel', 'Lang'];
  final buckets = {for (final l in labels) l: <SelfGameStatsRow>[]};
  final third = withDuration.length / 3;
  for (var i = 0; i < withDuration.length; i++) {
    final label = i < third ? 'Kurz' : (i < 2 * third ? 'Mittel' : 'Lang');
    buckets[label]!.add(withDuration[i]);
  }

  return [
    for (final l in labels)
      BucketWinStats(
        label: l,
        gamesPlayed: buckets[l]!.length,
        wins: buckets[l]!.where((r) => r.isWinner).length,
      ),
  ];
}

/// Siegquote nach Farbidentität, über alle Decks mit derselben
/// Farbkombination hinweg (im Unterschied zu PlayerStats.byDeck, das
/// nach einzelnem Deck aufschlüsselt). Partien ohne Deck-Angabe
/// landen gesammelt unter "Kein Deck angegeben".
List<BucketWinStats> computeWinRateByColorIdentity(
  List<SelfGameStatsRow> rows,
) {
  final byColor = <String, List<SelfGameStatsRow>>{};
  for (final r in rows) {
    final key = r.colorIdentity.isEmpty
        ? 'Kein Deck angegeben'
        : r.colorIdentity;
    byColor.putIfAbsent(key, () => []).add(r);
  }

  return [
    for (final entry in byColor.entries)
      BucketWinStats(
        label: entry.key,
        gamesPlayed: entry.value.length,
        wins: entry.value.where((r) => r.isWinner).length,
      ),
  ]..sort((a, b) => b.gamesPlayed.compareTo(a.gamesPlayed));
}

/// Elo-artiger Performance-Score des Ich-Spielers, auf 0-100 normiert.
///
/// Mit dem Nutzer abgestimmter Umfang (siehe ARCHITECTURE.md): KEIN
/// vollwertiges Multiplayer-Elo mit gegenseitig abhängigen
/// Spieler-Ratings - nur der Ich-Spieler bekommt einen Score, andere
/// Teilnehmer werden nicht bewertet. Berechnung:
/// - Partien werden chronologisch (nach playedAt) durchlaufen, das
///   Rating startet bei 1500 (Elo-Standardwert).
/// - Je Partie wird ein "tatsächliches Ergebnis" S in [0, 1] ermittelt:
///   bei Unentschieden 0.5; sonst, wenn eine Einzelplatzierung
///   vorliegt (Commander/cEDH), normiert aus dem Platz
///   `(participantCount - placement) / (participantCount - 1)`
///   (1. Platz = 1.0, letzter Platz = 0.0); sonst (Team-Modi ohne
///   Einzelplatzierung wie 2HG/Erzfeind, oder fehlende Daten)
///   ersatzweise Sieg/Niederlage (1.0 / 0.0).
/// - Da keine Gegner-Ratings erfasst werden, gilt als Erwartungswert
///   je Partie neutral 0.5 ("durchschnittlich starke Gegner").
///   Rating-Änderung = K * (S - 0.5), K = 32.
/// - Das Endrating wird über die normale Elo-Erwartungsformel auf
///   0-100 abgebildet (1500 -> 50, +-400 Rating -> ca. +-91/9) - der
///   Wert entspricht damit der geschätzten Gewinnwahrscheinlichkeit
///   gegen einen durchschnittlichen (1500er) Gegner.
class EloScore {
  final double rating;
  final int gamesCounted;

  const EloScore({required this.rating, required this.gamesCounted});

  int get score0to100 {
    final expected = 1 / (1 + math.pow(10, -(rating - 1500) / 400));
    return (expected * 100).round().clamp(0, 100);
  }

  static const empty = EloScore(rating: 1500, gamesCounted: 0);
}

EloScore computeEloScore(List<SelfGameStatsRow> rows) {
  if (rows.isEmpty) return EloScore.empty;

  const k = 32.0;
  final sorted = [...rows]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
  var rating = 1500.0;

  for (final row in sorted) {
    double actual;
    if (row.isDraw) {
      actual = 0.5;
    } else if (row.placement != null && row.participantCount > 1) {
      actual =
          (row.participantCount - row.placement!) / (row.participantCount - 1);
    } else {
      actual = row.isWinner ? 1.0 : 0.0;
    }
    const expected = 0.5;
    rating += k * (actual - expected);
  }

  return EloScore(rating: rating, gamesCounted: sorted.length);
}

/// Kurzes Textlabel zum 0-100-Elo-Score - für das Barometer im
/// Home-Dashboard (siehe elo_score_card.dart). Schwellenwerte 1:1 von
/// "playerDominanceLabel" aus mtg_stats_tracker übernommen (dort für
/// einen anderen, eigenen Score genutzt) - passen aber auch hier, da
/// beide Scores 0-100 mit 50 = durchschnittlich sind.
String eloScoreLabel(int score0to100) {
  if (score0to100 >= 85) return 'Grandios';
  if (score0to100 >= 70) return 'Sehr stark';
  if (score0to100 >= 55) return 'Stark';
  if (score0to100 >= 40) return 'Durchschnitt';
  return 'Ausbaufähig';
}
