import 'package:drift/drift.dart';

import '../../../../database/app_database.dart';
import '../../model/game_participant_draft.dart';
import '../../model/live_participant.dart';

/// Aufbereitete Teilnehmer-Zeile für die Anzeige: löst bekannte
/// Spieler/Decks per Join zu Namen auf, anonyme Teilnehmer bleiben bei
/// ihrem Label/ihrer Farbidentität.
class GameParticipantView {
  final int id;
  final String displayName;
  final String? deckName;
  final String colorIdentity;
  final bool isWinner;
  final bool isAnonymous;
  final int? startPosition;
  final int? placement;
  final String? team;

  const GameParticipantView({
    required this.id,
    required this.displayName,
    this.deckName,
    required this.colorIdentity,
    required this.isWinner,
    required this.isAnonymous,
    this.startPosition,
    this.placement,
    this.team,
  });
}

/// Eine abgeschlossene Partien-Teilnahme des Ich-Spielers, aufbereitet
/// für das Statistik-Dashboard (siehe lib/features/stats/). Enthält
/// bewusst nur, was dort für Siegquote gesamt/pro Deck sowie die
/// Gruppen-Filterung gebraucht wird - kein vollständiges Partien-Modell.
class SelfGameStatsRow {
  final int gameId;
  final int? groupId;
  final GameMode mode;
  final int? deckId;
  final String? deckName;
  final String colorIdentity;
  final bool isWinner;
  final DateTime playedAt;

  /// Platzierung des Ich-Spielers in dieser Partie (1 = Sieger), sofern
  /// erfasst - bei Team-Modi (2HG/Erzfeind) oft ungesetzt.
  final int? placement;

  /// Zugreihenfolge/Sitzposition des Ich-Spielers (1..participantCount),
  /// sofern erfasst.
  final int? startPosition;

  /// Gesamtzahl der Teilnehmer dieser Partie (alle Sitzplätze, nicht
  /// nur bekannte Spieler) - Grundlage für die partiengrößen-
  /// unabhängige Normierung von placement/startPosition in
  /// player_performance_stats.dart.
  final int participantCount;

  /// Gesamtdauer der Partie in Sekunden, nur bei Live-Erfassung gesetzt
  /// (siehe Games.durationSeconds).
  final int? durationSeconds;

  final bool isDraw;

  /// True, wenn in dieser Partie ein ANDERER Teilnehmer eines der
  /// EIGENEN Decks des Ich-Spielers gespielt hat (Deck-Verleih, siehe
  /// select_deck_dialog.dart/add_known_participant_dialog.dart) -
  /// Grundlage für das "shame"-Badge ("Ehrenwerte Niederlage", siehe
  /// achievement_engine.dart).
  final bool opponentPlayedOwnDeck;

  /// Umgekehrter Fall des Deck-Verleihs: true, wenn das vom
  /// Ich-Spieler in DIESER Partie gespielte Deck (falls vorhanden)
  /// tatsächlich Decks.ownerPlayerId == Ich-Spieler ist - also KEIN
  /// geliehenes fremdes Deck. Ohne Deck-Angabe (deckId == null)
  /// ebenfalls true (kein Fremd-Deck erkennbar). Grundlage für die
  /// Aufteilung "Eigene Decks"/"Decks anderer" in der
  /// "Nach Deck"-Statistik, siehe stats_screen.dart.
  final bool isOwnDeck;

  const SelfGameStatsRow({
    required this.gameId,
    required this.groupId,
    required this.mode,
    required this.deckId,
    required this.deckName,
    required this.colorIdentity,
    required this.isWinner,
    required this.playedAt,
    required this.placement,
    required this.startPosition,
    required this.participantCount,
    required this.durationSeconds,
    required this.isDraw,
    required this.opponentPlayedOwnDeck,
    required this.isOwnDeck,
  });
}

/// Eine Partie samt roher, durchsuchbarer Begriffe (Spielernamen -
/// bekannt oder anonym -, Deckname, Commander/Zweit-Commander aller
/// Teilnehmer) - Grundlage fuer die Suche in der Partien-Uebersicht
/// (siehe games_overview_screen.dart, Nutzerwunsch "nach Spieler,
/// Commander oder Deck suchen"). [searchTerms] ist bewusst roh (nicht
/// kleingeschrieben) - der Vergleich passiert erst beim Filtern in
/// der UI.
class GameListItem {
  final Game game;
  final List<String> searchTerms;

  const GameListItem({required this.game, required this.searchTerms});
}

class GamesRepository {
  final AppDatabase db;

  GamesRepository(this.db);

  /// [limit] ist standardmaessig OHNE Begrenzung (Nutzer-Feedback: die
  /// Partien-Uebersicht sollte trotz ihres eigenen Klassenkommentars
  /// "Historie ALLER erfassten Partien" tatsaechlich nicht bei den
  /// letzten 50 abschneiden) - optional weiterhin angebbar, falls eine
  /// zukuenftige Stelle (z. B. ein "Letzte Partien"-Widget) bewusst
  /// nur eine Teilmenge braucht.
  Stream<List<Game>> watchRecentGames({int? limit}) {
    final query = db.select(db.games)
      ..orderBy([
        (g) => OrderingTerm(expression: g.playedAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    return query.watch();
  }

  /// Wie [watchRecentGames] (unbegrenzt, neueste zuerst), aber jede
  /// Partie zusaetzlich mit den durchsuchbaren Begriffen ihrer
  /// Teilnehmer angereichert (siehe [GameListItem]). LEFT JOIN ab
  /// Games (nicht ab GameParticipants), damit auch eine Partie ganz
  /// ohne Teilnehmer nicht aus der Liste faellt.
  Stream<List<GameListItem>> watchGamesWithSearchTerms() {
    final query = db.select(db.games).join([
      leftOuterJoin(
        db.gameParticipants,
        db.gameParticipants.gameId.equalsExp(db.games.id),
      ),
      leftOuterJoin(
        db.players,
        db.players.id.equalsExp(db.gameParticipants.playerId),
      ),
      leftOuterJoin(
        db.decks,
        db.decks.id.equalsExp(db.gameParticipants.deckId),
      ),
    ]);

    return query.watch().map((rows) {
      final byGame = <int, List<TypedResult>>{};
      for (final row in rows) {
        final gameId = row.readTable(db.games).id;
        byGame.putIfAbsent(gameId, () => []).add(row);
      }

      final result = <GameListItem>[];
      for (final rowsForGame in byGame.values) {
        final game = rowsForGame.first.readTable(db.games);
        final terms = <String>[];
        for (final row in rowsForGame) {
          final participant = row.readTableOrNull(db.gameParticipants);
          if (participant == null) continue;
          final player = row.readTableOrNull(db.players);
          final deck = row.readTableOrNull(db.decks);
          if (player != null) terms.add(player.name);
          final anonymousLabel = participant.anonymousLabel;
          if (anonymousLabel != null && anonymousLabel.isNotEmpty) {
            terms.add(anonymousLabel);
          }
          if (deck != null) {
            terms.add(deck.name);
            final commander = deck.commanderName;
            if (commander != null && commander.isNotEmpty) {
              terms.add(commander);
            }
            final commander2 = deck.secondCommanderName;
            if (commander2 != null && commander2.isNotEmpty) {
              terms.add(commander2);
            }
          }
        }
        result.add(GameListItem(game: game, searchTerms: terms));
      }
      result.sort((a, b) => b.game.playedAt.compareTo(a.game.playedAt));
      return result;
    });
  }

  Stream<Game?> watchGameById(int gameId) {
    final query = db.select(db.games)..where((g) => g.id.equals(gameId));
    return query.watchSingleOrNull();
  }

  /// Wie [watchParticipants], aber mit aufgelösten Namen für bekannte
  /// Spieler/Decks (per Join) - Basis für die Partien-Detailansicht.
  Stream<List<GameParticipantView>> watchParticipantViews(int gameId) {
    final query = db.select(db.gameParticipants).join([
      leftOuterJoin(
        db.players,
        db.players.id.equalsExp(db.gameParticipants.playerId),
      ),
      leftOuterJoin(
        db.decks,
        db.decks.id.equalsExp(db.gameParticipants.deckId),
      ),
    ])
      ..where(db.gameParticipants.gameId.equals(gameId));

    return query.watch().map((rows) {
      return [
        for (final row in rows)
          _toParticipantView(
            row.readTable(db.gameParticipants),
            row.readTableOrNull(db.players),
            row.readTableOrNull(db.decks),
          ),
      ];
    });
  }

  GameParticipantView _toParticipantView(
    GameParticipant participant,
    Player? player,
    Deck? deck,
  ) {
    return GameParticipantView(
      id: participant.id,
      displayName: player?.name ??
          participant.anonymousLabel ??
          'Unbekannter Spieler',
      deckName: deck?.name,
      colorIdentity:
          deck?.colorIdentity ?? participant.anonymousColorIdentity ?? '',
      isWinner: participant.isWinner,
      isAnonymous: participant.playerId == null,
      startPosition: participant.startPosition,
      placement: participant.placement,
      team: participant.team,
    );
  }

  Stream<List<GameParticipant>> watchParticipants(int gameId) {
    final query = db.select(db.gameParticipants)
      ..where((p) => p.gameId.equals(gameId));
    return query.watch();
  }

  /// Alle ABGESCHLOSSENEN Partien-Teilnahmen des Ich-Spielers - Basis
  /// für das Statistik-Dashboard (lib/features/stats/). inProgress-
  /// Partien werden ausgeklammert, da dort noch keine Platzierung
  /// feststeht. Die Gruppen-Filterung (global vs. eine bestimmte
  /// Gruppe) passiert bewusst NICHT hier, sondern client-seitig im
  /// StatsScreen über [SelfGameStatsRow.groupId] - die Liste ist pro
  /// Nutzer klein genug, dass ein Umschalten des Filters keinen neuen
  /// DB-Stream braucht.
  Stream<List<SelfGameStatsRow>> watchSelfGameStats(int selfPlayerId) {
    // Bewusst NICHT nach playerId gefiltert: participantCount (Basis der
    // Startpositions-/Elo-Auswertung in player_performance_stats.dart)
    // braucht alle Sitzplätze jeder Partie, nicht nur den des
    // Ich-Spielers. Die Filterung auf den Ich-Spieler passiert danach
    // beim Gruppieren nach gameId in Dart.
    final query = db.select(db.gameParticipants).join([
      innerJoin(
        db.games,
        db.games.id.equalsExp(db.gameParticipants.gameId),
      ),
      leftOuterJoin(
        db.decks,
        db.decks.id.equalsExp(db.gameParticipants.deckId),
      ),
    ])
      ..where(db.games.status.equalsValue(GameStatus.completed));

    return query.watch().map((rows) {
      final byGame = <int, List<TypedResult>>{};
      for (final row in rows) {
        final gameId = row.readTable(db.games).id;
        byGame.putIfAbsent(gameId, () => []).add(row);
      }

      final result = <SelfGameStatsRow>[];
      for (final participantsInGame in byGame.values) {
        TypedResult? selfRow;
        for (final row in participantsInGame) {
          if (row.readTable(db.gameParticipants).playerId == selfPlayerId) {
            selfRow = row;
            break;
          }
        }
        if (selfRow == null) continue;

        // Deck-Verleih-Erkennung: spielt irgendein ANDERER Teilnehmer
        // dieser Partie ein Deck, dessen wahrer Besitzer der
        // Ich-Spieler ist (Decks.ownerPlayerId), unabhängig davon wer
        // es laut GameParticipants.deckId tatsächlich spielt? Siehe
        // SelfGameStatsRow.opponentPlayedOwnDeck.
        var opponentPlayedOwnDeck = false;
        for (final row in participantsInGame) {
          final participant = row.readTable(db.gameParticipants);
          if (participant.playerId == selfPlayerId) continue;
          final deck = row.readTableOrNull(db.decks);
          if (deck != null && deck.ownerPlayerId == selfPlayerId) {
            opponentPlayedOwnDeck = true;
            break;
          }
        }

        result.add(
          _toSelfStatsRow(
            selfRow.readTable(db.gameParticipants),
            selfRow.readTable(db.games),
            selfRow.readTableOrNull(db.decks),
            participantsInGame.length,
            opponentPlayedOwnDeck: opponentPlayedOwnDeck,
            selfPlayerId: selfPlayerId,
          ),
        );
      }
      result.sort((a, b) => a.playedAt.compareTo(b.playedAt));
      return result;
    });
  }

  SelfGameStatsRow _toSelfStatsRow(
    GameParticipant participant,
    Game game,
    Deck? deck,
    int participantCount, {
    required bool opponentPlayedOwnDeck,
    required int selfPlayerId,
  }) {
    return SelfGameStatsRow(
      gameId: game.id,
      groupId: game.groupId,
      mode: game.mode,
      deckId: deck?.id,
      deckName: deck?.name,
      colorIdentity: deck?.colorIdentity ?? '',
      isWinner: participant.isWinner,
      playedAt: game.playedAt,
      placement: participant.placement,
      startPosition: participant.startPosition,
      participantCount: participantCount,
      durationSeconds: game.durationSeconds,
      isDraw: game.isDraw,
      opponentPlayedOwnDeck: opponentPlayedOwnDeck,
      isOwnDeck: deck == null || deck.ownerPlayerId == selfPlayerId,
    );
  }

  /// Legt eine manuell nachgetragene, sofort abgeschlossene Partie an.
  Future<int> createManualGame({
    required DateTime playedAt,
    required GameMode mode,
    String? notes,
    int? groupId,
    required List<GameParticipantDraft> participants,
    bool isDraw = false,
  }) {
    return db.transaction(() async {
      final gameId = await db.into(db.games).insert(
            GamesCompanion.insert(
              playedAt: playedAt,
              mode: mode,
              notes: Value(notes),
              groupId: Value(groupId),
              entryMode: GameEntryMode.manual,
              status: GameStatus.completed,
              isDraw: Value(isDraw),
            ),
          );
      for (final p in participants) {
        await _insertParticipant(gameId, p);
      }
      return gameId;
    });
  }

  /// Startet eine Live-Partie (status = inProgress) und legt die
  /// Teilnehmer inkl. Start-Lebenspunkten an. Gibt die Game-id sowie,
  /// in derselben Reihenfolge wie [participants], die neu erzeugten
  /// GameParticipants-ids zurück.
  Future<(int gameId, List<int> participantIds)> startLiveGame({
    required GameMode mode,
    int? groupId,
    required List<GameParticipantDraft> participants,
  }) {
    return db.transaction(() async {
      final now = DateTime.now();
      final gameId = await db.into(db.games).insert(
            GamesCompanion.insert(
              playedAt: now,
              mode: mode,
              groupId: Value(groupId),
              entryMode: GameEntryMode.live,
              status: GameStatus.inProgress,
              startedAt: Value(now),
            ),
          );
      final ids = <int>[];
      for (final p in participants) {
        final id = await _insertParticipant(gameId, p);
        ids.add(id);
      }
      return (gameId, ids);
    });
  }

  Future<int> _insertParticipant(int gameId, GameParticipantDraft p) {
    return db.into(db.gameParticipants).insert(
          GameParticipantsCompanion.insert(
            gameId: gameId,
            playerId: Value(p.playerId),
            deckId: Value(p.deckId),
            anonymousLabel: Value(p.anonymousLabel),
            anonymousColorIdentity:
                Value(p.isAnonymous ? p.colorIdentity : null),
            isWinner: Value(p.isWinner),
            team: Value(p.team),
            startingLife: Value(p.startingLife),
            startPosition: Value(p.startPosition),
            placement: Value(p.placement),
            tableSide: Value(p.tableSide),
          ),
        );
  }

  /// Baut die Teilnehmerliste zum FORTSETZEN einer noch laufenden
  /// Live-Partie (Nutzerwunsch: aus der Partien-Übersicht/-Detailseite
  /// heraus eine "hängengebliebene" Live-Partie - z. B. nach
  /// Verlassen des Live-Screens per Zurück-Taste - weiter erfassen
  /// oder abschließen können). Liefert dieselbe Struktur wie die
  /// Teilnehmer beim erstmaligen Start ([LiveParticipant] über
  /// [startLiveGame]), aber mit dem AKTUELLEN Lebenspunkte-Stand statt
  /// der ursprünglichen Start-Lebenspunkte: pro Teilnehmer wird das
  /// zeitlich letzte LifeEvent herangezogen (resultingLife), ohne
  /// eigenes Event bleibt es bei GameParticipants.startingLife.
  Future<List<LiveParticipant>> loadLiveParticipants(int gameId) async {
    final query = db.select(db.gameParticipants).join([
      leftOuterJoin(
        db.players,
        db.players.id.equalsExp(db.gameParticipants.playerId),
      ),
    ])
      ..where(db.gameParticipants.gameId.equals(gameId))
      ..orderBy([
        OrderingTerm(expression: db.gameParticipants.startPosition),
      ]);
    final rows = await query.get();

    final result = <LiveParticipant>[];
    for (final row in rows) {
      final participant = row.readTable(db.gameParticipants);
      final player = row.readTableOrNull(db.players);
      final lastEvent = await (db.select(db.lifeEvents)
            ..where((e) => e.gameParticipantId.equals(participant.id))
            ..orderBy([
              (e) => OrderingTerm(
                    expression: e.occurredAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(1))
          .getSingleOrNull();
      result.add(
        LiveParticipant(
          gameParticipantId: participant.id,
          displayName: player?.name ??
              participant.anonymousLabel ??
              'Unbekannter Spieler',
          startingLife:
              lastEvent?.resultingLife ?? participant.startingLife ?? 0,
          team: participant.team,
          startPosition: participant.startPosition,
          tableSide: participant.tableSide,
        ),
      );
    }
    return result;
  }

  /// Bricht eine noch laufende Live-Partie vollständig ab (Nutzerwunsch:
  /// Gegenstück zum Fortsetzen oben - eine "hängengebliebene" Partie
  /// muss sich auch verwerfen lassen). Löscht alle LifeEvents ihrer
  /// Teilnehmer, die Teilnehmer selbst und zuletzt die Partie -
  /// unwiderruflich. Bewusst KEIN "soft delete"/eigener Status: eine
  /// abgebrochene Partie hat keinerlei Aussagewert, der aufbewahrt
  /// werden müsste (sie wäre wegen status == inProgress ohnehin nie in
  /// watchSelfGameStats/die Statistik eingeflossen). Keine Drift-
  /// Kaskaden auf den Tabellen konfiguriert, daher hier manuell in der
  /// richtigen Reihenfolge (LifeEvents -> GameParticipants -> Games).
  Future<void> cancelLiveGame(int gameId) {
    return db.transaction(() async {
      final participantIds = await (db.select(db.gameParticipants)
            ..where((p) => p.gameId.equals(gameId)))
          .map((p) => p.id)
          .get();
      for (final id in participantIds) {
        await (db.delete(db.lifeEvents)
              ..where((e) => e.gameParticipantId.equals(id)))
            .go();
      }
      await (db.delete(db.gameParticipants)
            ..where((p) => p.gameId.equals(gameId)))
          .go();
      await (db.delete(db.games)..where((g) => g.id.equals(gameId))).go();
    });
  }

  /// Protokolliert eine Lebenspunkte-Änderung während einer Live-Partie
  /// und setzt bei Bedarf automatisch "First Blood" (der zeitlich erste
  /// negative Lebenspunkte-Wechsel über alle Teilnehmer der Partie).
  Future<void> recordLifeChange({
    required int gameId,
    required int gameParticipantId,
    required int delta,
    required int resultingLife,
  }) {
    return db.transaction(() async {
      await db.into(db.lifeEvents).insert(
            LifeEventsCompanion.insert(
              gameParticipantId: gameParticipantId,
              delta: delta,
              resultingLife: resultingLife,
            ),
          );
      if (delta < 0) {
        final game = await (db.select(db.games)
              ..where((g) => g.id.equals(gameId)))
            .getSingle();
        if (game.firstBloodParticipantId == null) {
          await (db.update(db.games)..where((g) => g.id.equals(gameId)))
              .write(
            GamesCompanion(
              firstBloodParticipantId: Value(gameParticipantId),
            ),
          );
        }
      }
    });
  }

  /// Schließt eine Live-Partie ab: setzt status=completed, berechnet
  /// die Dauer und schreibt die am Ende festgelegte Platzierung
  /// (gameParticipantId -> Platz) je Teilnehmer - isWinner wird daraus
  /// abgeleitet (Platz 1). [placements] muss bereits über
  /// game_setup_validator.validateGameResult geprüft worden sein.
  Future<void> finishLiveGame({
    required int gameId,
    required DateTime startedAt,
    required Map<int, int> placements,
    bool isDraw = false,
  }) {
    return db.transaction(() async {
      final duration = DateTime.now().difference(startedAt).inSeconds;
      await (db.update(db.games)..where((g) => g.id.equals(gameId))).write(
        GamesCompanion(
          status: const Value(GameStatus.completed),
          durationSeconds: Value(duration),
          isDraw: Value(isDraw),
        ),
      );
      for (final entry in placements.entries) {
        await (db.update(db.gameParticipants)
              ..where((p) => p.id.equals(entry.key)))
            .write(
          GameParticipantsCompanion(
            placement: Value(entry.value),
            isWinner: Value(entry.value == 1),
          ),
        );
      }
    });
  }
}
