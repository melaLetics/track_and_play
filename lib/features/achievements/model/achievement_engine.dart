import '../../../database/app_database.dart';
import '../../games/controller/repository/games_repository.dart';
import 'achievement_status.dart';
import 'badge_definitions.dart';

/// Berechnet den Freischalt-Status ALLER Badges aus dem Katalog
/// (badge_definitions.dart) für den Ich-Spieler, aus [rows] - ALLEN
/// abgeschlossenen Partien-Teilnahmen des Ich-Spielers, UNGEFILTERT
/// nach Gruppe/Modus (mit dem Nutzer abgestimmt: Achievements zählen
/// bewusst global pro Spieler über alle Gruppen hinweg, siehe
/// ARCHITECTURE.md - im Unterschied zum Statistik-Dashboard, das eine
/// Gruppen-/Modus-Filterung anbietet). Reine Funktion ohne DB-Zugriff,
/// analog zu player_stats.dart/player_performance_stats.dart.
///
/// Die konkreten Freischalt-Regeln sind 1:1 aus dem alten
/// mtg_stats_tracker portiert (calc_win_streak.dart,
/// calc_played_games.dart, calc_won_games.dart,
/// calc_color_championships.dart, calc_weekday_streak.dart,
/// calc_special_moments.dart) - dort waren sie bereits gegen echte
/// Nutzerdaten erprobt. Das "shame"-Badge ("Ehrenwerte Niederlage" -
/// Niederlage gegen einen Gegner, der dabei eines der EIGENEN Decks
/// spielt) war eine Zeit lang strukturell nicht erreichbar, da Decks
/// zunächst fest ihrem Besitzer zugeordnet waren - seit es echten
/// Deck-Verleih gibt (siehe select_deck_dialog.dart/
/// add_known_participant_dialog.dart, ARCHITECTURE.md), ist es wieder
/// aktiv, siehe Kommentar in `_computeSpecial` unten.
Map<String, AchievementStatus> computeAchievements(
  List<SelfGameStatsRow> rows,
) {
  final sorted = [...rows]..sort((a, b) => a.playedAt.compareTo(b.playedAt));

  return {
    ..._computeStreaks(sorted),
    ..._computeMatches(sorted),
    ..._computeWins(sorted),
    ..._computeColorChampion(sorted),
    ..._computeWeekday(sorted),
    ..._computeSpecial(sorted),
  };
}

// --- Sieg-Serien --------------------------------------------------

Map<String, AchievementStatus> _computeStreaks(List<SelfGameStatsRow> sorted) {
  final achievedAt = <int, DateTime>{};
  // Wie oft eine Sieg-Serie GENAU dieser Länge erreicht wurde (siehe
  // AchievementStatus.timesAchieved) - jede Serie durchläuft jede
  // Schwelle beim Hochzählen genau einmal, ein erneutes Erreichen
  // zählt als weiteres Mal (Nutzeranforderung: diese Badges lassen
  // sich mehrfach "erarbeiten").
  final timesAchieved = <int, int>{};
  var currentStreak = 0;
  for (final row in sorted) {
    if (row.isWinner) {
      currentStreak++;
      if (streakThresholds.contains(currentStreak)) {
        // achievedAt wird bei jedem erneuten Erreichen dieser
        // Serienlänge überschrieben - das Badge zeigt damit den
        // ZULETZT erreichten Zeitpunkt (1:1 aus calc_win_streak.dart
        // übernommen).
        achievedAt[currentStreak] = row.playedAt;
        timesAchieved[currentStreak] = (timesAchieved[currentStreak] ?? 0) + 1;
      }
    } else {
      currentStreak = 0;
    }
  }
  return {
    for (final n in streakThresholds)
      'streak_$n': achievedAt.containsKey(n)
          ? AchievementStatus(
              unlocked: true,
              achievedAt: achievedAt[n],
              timesAchieved: timesAchieved[n],
            )
          : AchievementStatus.locked,
  };
}

// --- Partien / Siege ------------------------------------------------

Map<String, AchievementStatus> _computeMatches(List<SelfGameStatsRow> sorted) {
  return {
    for (final n in matchThresholds)
      'matches_$n': sorted.length >= n
          ? AchievementStatus(unlocked: true, achievedAt: sorted[n - 1].playedAt)
          : AchievementStatus.locked,
  };
}

Map<String, AchievementStatus> _computeWins(List<SelfGameStatsRow> sorted) {
  final wins = sorted.where((r) => r.isWinner).toList();
  return {
    for (final n in winThresholds)
      'wins_$n': wins.length >= n
          ? AchievementStatus(unlocked: true, achievedAt: wins[n - 1].playedAt)
          : AchievementStatus.locked,
  };
}

// --- Farbchampion --------------------------------------------------

const _monoColors = ['w', 'u', 'b', 'r', 'g'];

/// Wandelt die (bereits WUBRG-sortiert gespeicherte, siehe
/// Decks.colorIdentity) Farbidentität eines Decks in den in
/// badge_definitions.dart verwendeten Schlüssel um ('w'..'g' für
/// einfarbig, z. B. 'wu' für zweifarbig, 'wubrg' für fünffarbig, 'n'
/// für farblos). Da Decks.colorIdentity bereits WUBRG-sortiert
/// gespeichert wird, genügt Kleinschreibung - die zwei-/drei-/
/// vierfarbigen Kombinationen in badge_definitions.dart sind exakt
/// die WUBRG-sortierten Buchstabenfolgen.
String _colorKey(String colorIdentity) {
  if (colorIdentity.isEmpty) return 'n';
  if (colorIdentity.length >= 5) return 'wubrg';
  return colorIdentity.toLowerCase();
}

Map<String, AchievementStatus> _computeColorChampion(
  List<SelfGameStatsRow> sorted,
) {
  final result = <String, AchievementStatus>{
    for (final b in colorChampionBadges) b.id: AchievementStatus.locked,
  };

  // Pro einfarbiger Farbe die Menge der unterschiedlichen Decks, mit
  // denen bereits gewonnen wurde - 1., 2. und 3. unterschiedliches
  // Deck schalten Basis-/Master-/Champion-Stufe frei (1:1 aus
  // calc_color_championships.dart: number==1 -> Basis, ==2 ->
  // "_master", >=3 -> "_champ").
  final monoWonDecks = <String, Set<int>>{
    for (final c in _monoColors) c: <int>{},
  };

  for (final row in sorted) {
    if (!row.isWinner || row.deckId == null) continue;
    final key = _colorKey(row.colorIdentity);

    String badgeId;
    if (key.length == 1 && key != 'n') {
      final decksForColor = monoWonDecks[key]!;
      final wasNewDeck = decksForColor.add(row.deckId!);
      if (!wasNewDeck) continue;
      final number = decksForColor.length;
      if (number > 3) continue;
      badgeId = switch (number) {
        1 => 'color_$key',
        2 => 'color_${key}_master',
        _ => 'color_${key}_champ',
      };
    } else {
      // Mehrfarbig, fünffarbig oder farblos: nur EIN Tier, es zählt
      // nur der erste Sieg mit einem Deck dieser Farbidentität.
      badgeId = 'color_$key';
    }

    if (result[badgeId]?.unlocked ?? false) continue;
    result[badgeId] = AchievementStatus(unlocked: true, achievedAt: row.playedAt);
  }

  return result;
}

// --- Wochentags-Serien -----------------------------------------------

const _weekdayNames = {
  DateTime.monday: 'monday',
  DateTime.tuesday: 'tuesday',
  DateTime.wednesday: 'wednesday',
  DateTime.thursday: 'thursday',
  DateTime.friday: 'friday',
  DateTime.saturday: 'saturday',
  DateTime.sunday: 'sunday',
};

/// Serienlängen für die Wochentags-Badges (nur 2/3/5 - kein 10er, wie
/// im alten mtg_stats_tracker und im Katalog in badge_definitions.dart).
const _weekdayStreakLengths = [2, 3, 5];

Map<String, AchievementStatus> _computeWeekday(List<SelfGameStatsRow> sorted) {
  final result = <String, AchievementStatus>{
    for (final b in weekdayBadges) b.id: AchievementStatus.locked,
  };

  // Für jeden Wochentag die Kalendertage sammeln, an denen der
  // Ich-Spieler mindestens eine Partie hatte (Mehrfach-Partien am
  // selben Tag zählen nur einmal).
  final playedDaysByWeekday = <int, Set<DateTime>>{
    for (final wd in _weekdayNames.keys) wd: <DateTime>{},
  };
  for (final row in sorted) {
    final d = row.playedAt;
    playedDaysByWeekday[DateTime(d.year, d.month, d.day).weekday]!
        .add(DateTime(d.year, d.month, d.day));
  }

  for (final weekday in _weekdayNames.keys) {
    final days = playedDaysByWeekday[weekday]!.toList()..sort();
    if (days.isEmpty) continue;

    // Letzter Zeitpunkt, an dem eine Serie der jeweiligen Länge
    // erreicht wurde (wird bei jedem erneuten Erreichen überschrieben
    // - 1:1 aus calc_weekday_streak.dart), sowie wie oft das insgesamt
    // vorkam (siehe AchievementStatus.timesAchieved, analog zu den
    // Sieg-Serien oben - auch Wochentags-Serien lassen sich mehrfach
    // "erarbeiten").
    final lastStreakDates = <int, DateTime>{};
    final streakCounts = <int, int>{};
    var currentStreak = 1;
    for (var i = 1; i < days.length; i++) {
      // Gleicher Wochentag: der Abstand muss exakt 7 Tage betragen,
      // damit es eine ununterbrochene wöchentliche Serie ist.
      if (days[i].difference(days[i - 1]).inDays == 7) {
        currentStreak++;
        if (_weekdayStreakLengths.contains(currentStreak)) {
          lastStreakDates[currentStreak] = days[i];
          streakCounts[currentStreak] = (streakCounts[currentStreak] ?? 0) + 1;
        }
      } else {
        currentStreak = 1;
      }
    }

    for (final weeks in _weekdayStreakLengths) {
      final date = lastStreakDates[weeks];
      if (date == null) continue;
      final badgeId =
          'weekday_${_weekdayNames[weekday]}_${weeks.toString().padLeft(2, '0')}';
      result[badgeId] = AchievementStatus(
        unlocked: true,
        achievedAt: date,
        timesAchieved: streakCounts[weeks],
      );
    }
  }

  return result;
}

// --- Spezial-Badges --------------------------------------------------

Map<String, AchievementStatus> _computeSpecial(List<SelfGameStatsRow> sorted) {
  final result = <String, AchievementStatus>{
    for (final b in specialBadges) b.id: AchievementStatus.locked,
  };

  if (sorted.isEmpty) return result;

  // NEWBIE - allererste jemals erfasste Partie.
  result['newbie'] =
      AchievementStatus(unlocked: true, achievedAt: sorted.first.playedAt);

  final wins = sorted.where((r) => r.isWinner).toList();
  if (wins.isNotEmpty) {
    // ERSTER SIEG
    result['first_win'] =
        AchievementStatus(unlocked: true, achievedAt: wins.first.playedAt);

    // GRANDIOS: erster Sieg als zuletzt gestarteter Spieler
    // (Startposition == Teilnehmerzahl) in einer Commander-Partie mit
    // mehr als 3 Teilnehmern - 1:1 aus calc_special_moments.dart
    // übernommen. Bewusst nur Commander (nicht cEDH), wie im
    // Original - cEDH gab es im alten mtg_stats_tracker noch nicht,
    // eine explizite Ausweitung auf cEDH wurde nicht abgestimmt.
    for (final row in wins) {
      if (row.mode == GameMode.commander &&
          row.participantCount > 3 &&
          row.startPosition == row.participantCount) {
        result['grandios'] =
            AchievementStatus(unlocked: true, achievedAt: row.playedAt);
        break;
      }
    }
  }

  // FIRST STRIKE: pro eigenem Deck das chronologisch erste jemals
  // damit gespielte Spiel - wenn eines dieser "ersten Spiele" gewonnen
  // wurde, zählt das früheste solche Datum über alle Decks hinweg.
  // Im alten mtg_stats_tracker konnte theoretisch auch ein ANDERER
  // Spieler das Deck zuerst spielen (Deck-Verleih); in diesem
  // Datenmodell ist ein Deck aber immer fest seinem Besitzer
  // zugeordnet (kein Deck-Verleih), wodurch "das erste Spiel des
  // Decks" hier automatisch immer selbst gespielt wird.
  final byDeck = <int, List<SelfGameStatsRow>>{};
  for (final row in sorted) {
    if (row.deckId == null) continue;
    byDeck.putIfAbsent(row.deckId!, () => []).add(row);
  }
  DateTime? firstStrikeDate;
  for (final deckRows in byDeck.values) {
    final firstGame = deckRows.first; // deckRows ist chronologisch (aus sorted aufgebaut)
    if (!firstGame.isWinner) continue;
    if (firstStrikeDate == null || firstGame.playedAt.isBefore(firstStrikeDate)) {
      firstStrikeDate = firstGame.playedAt;
    }
  }
  if (firstStrikeDate != null) {
    result['first_strike'] =
        AchievementStatus(unlocked: true, achievedAt: firstStrikeDate);
  }

  // SHAME ("Ehrenwerte Niederlage"): eine ECHT verlorene Partie
  // (weder Sieg noch Unentschieden), in der ein ANDERER Teilnehmer
  // eines der EIGENEN Decks des Ich-Spielers spielt (Deck-Verleih,
  // siehe SelfGameStatsRow.opponentPlayedOwnDeck / games_repository.
  // dart) - seit es echten Deck-Verleih gibt wieder erreichbar (war
  // zuvor strukturell gesperrt, siehe ARCHITECTURE.md). Frühestes
  // solches Datum zählt, analog zu first_win/first_strike oben.
  for (final row in sorted) {
    if (!row.isWinner && !row.isDraw && row.opponentPlayedOwnDeck) {
      result['shame'] =
          AchievementStatus(unlocked: true, achievedAt: row.playedAt);
      break;
    }
  }

  // WEEKEND WARRIOR: drei chronologisch aufeinanderfolgende
  // Kalendertage Freitag-Samstag-Sonntag mit je mindestens einer
  // Partie - 1:1 aus calc_special_moments.dart übernommen.
  if (sorted.length > 2) {
    final uniqueDates = sorted
        .map((r) => DateTime(r.playedAt.year, r.playedAt.month, r.playedAt.day))
        .toSet()
        .toList()
      ..sort();
    if (uniqueDates.length > 2) {
      for (var i = 0; i < uniqueDates.length - 2; i++) {
        final d1 = uniqueDates[i];
        final d2 = uniqueDates[i + 1];
        final d3 = uniqueDates[i + 2];
        final consecutive =
            d2.difference(d1).inDays == 1 && d3.difference(d2).inDays == 1;
        final isFriSatSun = d1.weekday == DateTime.friday &&
            d2.weekday == DateTime.saturday &&
            d3.weekday == DateTime.sunday;
        if (consecutive && isFriSatSun) {
          result['weekend'] = AchievementStatus(unlocked: true, achievedAt: d3);
          break;
        }
      }
    }
  }

  // 5 / 10 / 25 VERSCHIEDENE GEWONNENE DECKS
  final wonWithDecks = <int>{};
  for (final row in wins) {
    if (row.deckId == null) continue;
    final wasNewDeck = wonWithDecks.add(row.deckId!);
    if (!wasNewDeck) continue;
    final number = wonWithDecks.length;
    if (number == 5) {
      result['win_five_diff_decks'] =
          AchievementStatus(unlocked: true, achievedAt: row.playedAt);
    }
    if (number == 10) {
      result['win_ten_diff_decks'] =
          AchievementStatus(unlocked: true, achievedAt: row.playedAt);
    }
    if (number == 25) {
      result['win_twentyfive_diff_decks'] =
          AchievementStatus(unlocked: true, achievedAt: row.playedAt);
    }
  }

  return result;
}
