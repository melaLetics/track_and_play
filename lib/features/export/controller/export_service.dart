import '../../../database/app_database.dart';
import '../model/export_bundle.dart';
import '../model/export_selection.dart';

/// Baut ein [ExportBundle] aus der aktuellen Datenbank - für den
/// Datei-Export (komplette/teilweise Auswahl, siehe [ExportSelection])
/// sowie für den QR-Export (immer ein einzelnes Deck oder ein
/// einzelner Spieler, siehe [buildDeckQrBundle]/[buildPlayerQrBundle]).
///
/// Bewusst kein reiner Funktions-Stil wie z. B.
/// player_performance_stats.dart: das Bundle braucht mehrere
/// Datenbank-Lesezugriffe (Players/Decks/Groups/Games+Teilnehmer), die
/// hier direkt über [AppDatabase] gebündelt werden, statt die
/// beteiligten Repositories um export-spezifische Methoden zu
/// erweitern.
class ExportService {
  final AppDatabase db;

  const ExportService(this.db);

  Future<ExportBundle> build(ExportSelection selection) async {
    // Spieler-/Deck-/Gruppen-Namen werden IMMER vollständig geladen
    // (unabhängig von der Auswahl), da z. B. ein exportiertes Deck
    // oder eine exportierte Partie einen Spieler/eine Gruppe per Name
    // referenziert, auch wenn diese Kategorie selbst nicht
    // mitexportiert wird.
    final allPlayers = await db.select(db.players).get();
    final allDecks = await db.select(db.decks).get();
    final allGroups = await db.select(db.groups).get();
    final playerNameById = <int, String>{
      for (final p in allPlayers) p.id: p.name,
    };
    final deckById = <int, Deck>{for (final d in allDecks) d.id: d};
    final groupNameById = <int, String>{
      for (final g in allGroups) g.id: g.name,
    };

    final players = selection.includePlayers
        ? [for (final p in allPlayers) _toPlayerExport(p)]
        : <PlayerExport>[];

    final decks = selection.includeDecks
        ? [
            for (final d in allDecks)
              _toDeckExport(d, playerNameById[d.ownerPlayerId] ?? ''),
          ]
        : <DeckExport>[];

    var groups = <GroupExport>[];
    if (selection.includeGroups) {
      final memberships = await db.select(db.playerGroupMemberships).get();
      groups = [
        for (final g in allGroups)
          GroupExport(
            name: g.name,
            archived: g.archived,
            memberNames: [
              for (final m in memberships)
                if (m.groupId == g.id && playerNameById[m.playerId] != null)
                  playerNameById[m.playerId]!,
            ],
          ),
      ];
    }

    var games = <GameExport>[];
    if (selection.includeGames) {
      final completedGames = await (db.select(db.games)
            ..where((g) => g.status.equalsValue(GameStatus.completed)))
          .get();
      games = [
        for (final g in completedGames)
          await _toGameExport(
            g,
            playerNameById: playerNameById,
            deckById: deckById,
            groupNameById: groupNameById,
          ),
      ];
    }

    return ExportBundle(
      exportedAt: DateTime.now(),
      players: players,
      decks: decks,
      groups: groups,
      games: games,
    );
  }

  /// QR-Export eines einzelnen Decks: enthält zusätzlich den Besitzer
  /// als [PlayerExport] (ohne dessen andere Decks), damit die
  /// Gegenseite den Spieler beim Import optional mit anlegen kann.
  Future<ExportBundle> buildDeckQrBundle(int deckId) async {
    final deck =
        await (db.select(db.decks)..where((d) => d.id.equals(deckId)))
            .getSingle();
    final owner = await (db.select(db.players)
          ..where((p) => p.id.equals(deck.ownerPlayerId)))
        .getSingle();
    return ExportBundle(
      exportedAt: DateTime.now(),
      players: [_toPlayerExport(owner)],
      decks: [_toDeckExport(deck, owner.name)],
    );
  }

  /// QR-Export eines einzelnen Spielerprofils - bewusst OHNE dessen
  /// Decks (siehe ARCHITECTURE.md, mit dem Nutzer abgestimmte
  /// QR-Design-Entscheidung).
  Future<ExportBundle> buildPlayerQrBundle(int playerId) async {
    final player = await (db.select(db.players)
          ..where((p) => p.id.equals(playerId)))
        .getSingle();
    return ExportBundle(
      exportedAt: DateTime.now(),
      players: [_toPlayerExport(player)],
    );
  }

  /// QR-Export einer einzelnen abgeschlossenen Partie: enthält
  /// zusätzlich [PlayerExport]-Einträge für jeden bekannten Teilnehmer
  /// (damit sie beim Import optional als neue Spieler angelegt werden
  /// können), aber bewusst KEINE vollständigen [DeckExport]-Einträge -
  /// die Farbidentität jedes Teilnehmers steht bereits direkt auf
  /// [GameParticipantExport.colorIdentity], das reicht für die
  /// "on the fly"-Zuordnung zu einem eigenen Deck beim Import (siehe
  /// ImportService/ParticipantOverride) und hält den QR-Code klein.
  Future<ExportBundle> buildGameQrBundle(int gameId) async {
    final game =
        await (db.select(db.games)..where((g) => g.id.equals(gameId)))
            .getSingle();
    final allPlayers = await db.select(db.players).get();
    final allDecks = await db.select(db.decks).get();
    final allGroups = await db.select(db.groups).get();
    final playerNameById = <int, String>{
      for (final p in allPlayers) p.id: p.name,
    };
    final deckById = <int, Deck>{for (final d in allDecks) d.id: d};
    final groupNameById = <int, String>{
      for (final g in allGroups) g.id: g.name,
    };
    final gameExport = await _toGameExport(
      game,
      playerNameById: playerNameById,
      deckById: deckById,
      groupNameById: groupNameById,
    );

    final knownPlayerIds = <int>{};
    final participantRows = await (db.select(db.gameParticipants)
          ..where((p) => p.gameId.equals(gameId)))
        .get();
    for (final p in participantRows) {
      if (p.playerId != null) knownPlayerIds.add(p.playerId!);
    }

    return ExportBundle(
      exportedAt: DateTime.now(),
      players: [
        for (final p in allPlayers)
          if (knownPlayerIds.contains(p.id)) _toPlayerExport(p),
      ],
      games: [gameExport],
    );
  }

  PlayerExport _toPlayerExport(Player p) =>
      PlayerExport(name: p.name, archived: p.archived);

  DeckExport _toDeckExport(Deck d, String ownerName) => DeckExport(
        ownerName: ownerName,
        name: d.name,
        colorIdentity: d.colorIdentity,
        commanderName: d.commanderName,
        secondCommanderName: d.secondCommanderName,
        buildType: d.buildType?.name,
        bracket: d.bracket,
        isProxy: d.isProxy,
        isTournamentLegal: d.isTournamentLegal,
        deckLink: d.deckLink,
        archived: d.archived,
      );

  Future<GameExport> _toGameExport(
    Game g, {
    required Map<int, String> playerNameById,
    required Map<int, Deck> deckById,
    required Map<int, String> groupNameById,
  }) async {
    final participantRows = await (db.select(db.gameParticipants)
          ..where((p) => p.gameId.equals(g.id)))
        .get();
    int? firstBloodIndex;
    final participants = <GameParticipantExport>[];
    for (var i = 0; i < participantRows.length; i++) {
      final p = participantRows[i];
      if (g.firstBloodParticipantId != null &&
          p.id == g.firstBloodParticipantId) {
        firstBloodIndex = i;
      }
      final deck = p.deckId != null ? deckById[p.deckId] : null;
      // Deck-Verleih: das Deck gehoert einem ANDEREN Spieler als dem
      // Teilnehmer selbst (siehe GameParticipantDraft.deckOwnerName) -
      // erkennbar rein am Vergleich von Decks.ownerPlayerId mit
      // GameParticipants.playerId, kein eigenes DB-Feld noetig.
      final deckOwnerName = (deck != null && deck.ownerPlayerId != p.playerId)
          ? playerNameById[deck.ownerPlayerId]
          : null;
      participants.add(
        GameParticipantExport(
          playerName: p.playerId != null ? playerNameById[p.playerId] : null,
          deckName: deck?.name,
          deckOwnerName: deckOwnerName,
          anonymousLabel: p.anonymousLabel,
          anonymousColorIdentity: p.anonymousColorIdentity,
          colorIdentity: deck?.colorIdentity ?? p.anonymousColorIdentity ?? '',
          isWinner: p.isWinner,
          placement: p.placement,
          team: p.team,
          startingLife: p.startingLife,
          startPosition: p.startPosition,
        ),
      );
    }
    return GameExport(
      playedAt: g.playedAt,
      mode: g.mode.name,
      notes: g.notes,
      groupName: g.groupId != null ? groupNameById[g.groupId] : null,
      entryMode: g.entryMode.name,
      durationSeconds: g.durationSeconds,
      isDraw: g.isDraw,
      participants: participants,
      firstBloodParticipantIndex: firstBloodIndex,
    );
  }
}
