import '../../../database/app_database.dart';
import 'game_participant_draft.dart';

/// Teilnehmerzahl-Grenzen je Spielmodus. Portiert/adaptiert aus
/// mtg_stats_tracker (game_create_validator.dart), erweitert um die
/// vom Nutzer bestätigten Regeln für Erzfeind (Team 2-5 + 1 Erzfeind)
/// und Two-Headed Giant (zwei gleich große Teams, min. 2 pro Team -
/// bewusst flexibler als mtg_stats_tracker, das dort starr 2v2 war).
class GameModeRules {
  final int minParticipants;
  final int? maxParticipants;
  final bool requiresTeams;

  const GameModeRules({
    required this.minParticipants,
    this.maxParticipants,
    this.requiresTeams = false,
  });
}

const Map<GameMode, GameModeRules> gameModeRules = {
  GameMode.commander: GameModeRules(minParticipants: 2, maxParticipants: 6),
  GameMode.competitiveCommander:
      GameModeRules(minParticipants: 2, maxParticipants: 6),
  GameMode.archenemy: GameModeRules(
    minParticipants: 3,
    maxParticipants: 6,
    requiresTeams: true,
  ),
  GameMode.twoHeadedGiant:
      GameModeRules(minParticipants: 4, requiresTeams: true),
};

/// Prüft die Teilnehmerliste, BEVOR gespielt wird - also vor dem Start
/// einer Live-Partie oder als erster Teil der manuellen Erfassung.
/// Prüft absichtlich noch KEINE Platzierung (die steht bei Live-Partien
/// naturgemäß erst am Ende fest) - siehe [validateGameResult] dafür.
String? validateGameSetup({
  required GameMode mode,
  required List<GameParticipantDraft> participants,
}) {
  final rules = gameModeRules[mode]!;
  final count = participants.length;

  if (count < rules.minParticipants) {
    return 'Dieser Modus benötigt mindestens ${rules.minParticipants} Teilnehmer.';
  }
  if (rules.maxParticipants != null && count > rules.maxParticipants!) {
    return 'Dieser Modus erlaubt höchstens ${rules.maxParticipants} Teilnehmer.';
  }

  final knownIds =
      participants.map((p) => p.playerId).whereType<int>().toList();
  if (knownIds.toSet().length != knownIds.length) {
    return 'Ein Spieler kann nur einmal an derselben Partie teilnehmen.';
  }

  if (participants.any((p) => p.startPosition == null)) {
    return 'Bitte vergib für jeden Teilnehmer eine Startposition.';
  }
  final positions = participants.map((p) => p.startPosition!).toList();
  if (positions.toSet().length != positions.length) {
    return 'Jede Startposition darf nur einmal vergeben werden.';
  }

  if (mode == GameMode.archenemy) {
    final archenemyCount =
        participants.where((p) => p.team == 'archenemy').length;
    if (archenemyCount != 1) {
      return 'Im Erzfeind-Modus muss genau ein Teilnehmer als Erzfeind markiert sein.';
    }
    final teamCount = count - archenemyCount;
    if (teamCount < 2 || teamCount > 5) {
      return 'Das Team gegen den Erzfeind braucht 2 bis 5 Spieler.';
    }
  }

  if (mode == GameMode.twoHeadedGiant) {
    if (participants.any((p) => p.team == null || p.team!.isEmpty)) {
      return 'Bitte weise jedem Teilnehmer ein Team zu.';
    }
    final grouped = <String, int>{};
    for (final p in participants) {
      grouped[p.team!] = (grouped[p.team!] ?? 0) + 1;
    }
    if (grouped.length != 2) {
      return 'Two-Headed Giant benötigt genau zwei Teams.';
    }
    final sizes = grouped.values.toList();
    if (sizes[0] != sizes[1]) {
      return 'Beide Teams müssen gleich groß sein.';
    }
    if (sizes[0] < 2) {
      return 'Jedes Team braucht mindestens zwei Spieler.';
    }
  }

  return null;
}

/// Volle Prüfung inkl. Platzierung - vor dem manuellen Speichern bzw.
/// vor dem Beenden einer Live-Partie. Ruft [validateGameSetup] mit auf.
String? validateGameResult({
  required GameMode mode,
  required List<GameParticipantDraft> participants,
  required bool isDraw,
}) {
  final setupError = validateGameSetup(mode: mode, participants: participants);
  if (setupError != null) return setupError;

  if (participants.any((p) => p.placement == null)) {
    return 'Bitte vergib für jeden Teilnehmer eine Platzierung.';
  }

  final placements = participants.map((p) => p.placement!).toList();

  if (isDraw) {
    if (placements.toSet().length != 1) {
      return 'Bei einem Unentschieden müssen alle Teilnehmer denselben Platz belegen.';
    }
    return null;
  }

  switch (mode) {
    case GameMode.commander:
    case GameMode.competitiveCommander:
      final expected =
          List.generate(participants.length, (i) => i + 1).toSet();
      if (placements.toSet().length != placements.length ||
          placements.toSet().difference(expected).isNotEmpty) {
        return 'Die Platzierungen müssen eindeutig sein und von 1 bis '
            '${participants.length} reichen.';
      }
      break;

    case GameMode.archenemy:
      final archenemyPlacements = <int>{};
      final teamPlacements = <int>{};
      for (final p in participants) {
        if (p.team == 'archenemy') {
          archenemyPlacements.add(p.placement!);
        } else {
          teamPlacements.add(p.placement!);
        }
      }
      if (teamPlacements.length != 1) {
        return 'Alle Team-Mitglieder gegen den Erzfeind müssen denselben '
            'Platz belegen.';
      }
      if (archenemyPlacements.length != 1 ||
          archenemyPlacements.first == teamPlacements.first) {
        return 'Der Erzfeind muss einen anderen Platz belegen als das Team.';
      }
      if (!{1, 2}.contains(archenemyPlacements.first) ||
          !{1, 2}.contains(teamPlacements.first)) {
        return 'In diesem Modus gibt es nur Platz 1 und 2.';
      }
      break;

    case GameMode.twoHeadedGiant:
      final byTeam = <String, Set<int>>{};
      for (final p in participants) {
        byTeam.putIfAbsent(p.team!, () => {}).add(p.placement!);
      }
      if (byTeam.values.any((set) => set.length != 1)) {
        return 'Alle Mitglieder eines Teams müssen denselben Platz belegen.';
      }
      final teamPlacementValues = byTeam.values.map((s) => s.first).toSet();
      if (teamPlacementValues.length != 2) {
        return 'Die beiden Teams müssen unterschiedliche Plätze belegen.';
      }
      if (!teamPlacementValues.every((v) => v == 1 || v == 2)) {
        return 'In diesem Modus gibt es nur Platz 1 und 2.';
      }
      break;
  }

  return null;
}
