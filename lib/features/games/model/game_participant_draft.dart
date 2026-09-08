/// Ein Teilnehmer-Entwurf während der Partien-Erfassung (manuell oder
/// live), bevor er als GameParticipants-Zeile gespeichert wird.
///
/// Entweder bekannt (playerId gesetzt, optional deckId) oder anonym
/// (playerId null, anonymousLabel/colorIdentity beschreiben ihn).
class GameParticipantDraft {
  final int? playerId;
  final String? playerName;
  final int? deckId;
  final String? deckName;

  /// Falls gesetzt: das Deck (siehe [deckId]) gehört NICHT diesem
  /// Teilnehmer, sondern wurde sich von einem anderen Spieler geliehen
  /// (siehe AddKnownParticipantDialog/SelectDeckDialog, Eintrag
  /// "Geliehenes Deck"). Rein informativ für die Erfassung/Anzeige -
  /// die GameParticipants-Tabelle selbst braucht dafür kein eigenes
  /// Feld, da sich ein Deck-Verleih beim Lesen bereits aus einem
  /// Vergleich von GameParticipants.playerId mit Decks.ownerPlayerId
  /// ergibt (siehe games_repository.dart).
  final int? deckOwnerPlayerId;
  final String? deckOwnerName;

  final String? anonymousLabel;

  /// Farbidentität: bei bekanntem Deck vom Deck übernommen (nur zur
  /// Anzeige hier im Entwurf), bei anonymen Teilnehmern frei gewählt
  /// und wird dann als anonymousColorIdentity gespeichert.
  final String colorIdentity;

  final int? startingLife;

  /// Team-/Rollen-Kennung (siehe GameParticipants.team): Teamname bei
  /// Two-Headed Giant, "archenemy"/"team" bei Erzfeind, sonst null.
  final String? team;

  /// Zugreihenfolge (1..Teilnehmerzahl) - wird vor Spielbeginn auf dem
  /// Setup-Screen vergeben und muss über alle Teilnehmer eindeutig
  /// sein (siehe game_setup_validator.dart).
  final int? startPosition;

  /// Endplatzierung (1 = Sieger/Sieger-Team, 2 = nächster Platz, ...).
  /// Bei manueller Erfassung direkt beim Anlegen gesetzt, bei
  /// Live-Erfassung erst beim Beenden der Partie.
  final int? placement;

  const GameParticipantDraft({
    this.playerId,
    this.playerName,
    this.deckId,
    this.deckName,
    this.deckOwnerPlayerId,
    this.deckOwnerName,
    this.anonymousLabel,
    this.colorIdentity = '',
    this.startingLife,
    this.team,
    this.startPosition,
    this.placement,
  });

  bool get isAnonymous => playerId == null;

  /// Sieger-Status wird ausschließlich aus [placement] abgeleitet
  /// (Platz 1) - kein eigenständig gesetztes Feld mehr, damit
  /// Platzierung und Sieger-Markierung nie auseinanderlaufen können.
  bool get isWinner => placement == 1;

  String get displayName {
    if (playerName != null && playerName!.isNotEmpty) return playerName!;
    if (anonymousLabel != null && anonymousLabel!.isNotEmpty) {
      return anonymousLabel!;
    }
    return 'Unbekannter Spieler';
  }

  GameParticipantDraft copyWith({
    int? startingLife,
    String? team,
    int? startPosition,
    int? placement,
  }) {
    return GameParticipantDraft(
      playerId: playerId,
      playerName: playerName,
      deckId: deckId,
      deckName: deckName,
      deckOwnerPlayerId: deckOwnerPlayerId,
      deckOwnerName: deckOwnerName,
      anonymousLabel: anonymousLabel,
      colorIdentity: colorIdentity,
      startingLife: startingLife ?? this.startingLife,
      team: team ?? this.team,
      startPosition: startPosition ?? this.startPosition,
      placement: placement ?? this.placement,
    );
  }

  /// Ersetzt die Deck-Zuordnung (und die davon abgeleitete
  /// Farbidentität) durch eine neu getroffene Deck-Auswahl - für das
  /// nachträgliche Ändern des Decks eines bereits zur Partie
  /// hinzugefügten bekannten Teilnehmers (siehe SelectDeckDialog /
  /// GameSetupScreen). Bewusst kein Teil von [copyWith]: dort würde
  /// sich ein `deckId: null` (= "kein Deck angeben") nicht von
  /// "nicht ändern" unterscheiden lassen.
  GameParticipantDraft withDeck({
    int? deckId,
    String? deckName,
    String colorIdentity = '',
    int? deckOwnerPlayerId,
    String? deckOwnerName,
  }) {
    return GameParticipantDraft(
      playerId: playerId,
      playerName: playerName,
      deckId: deckId,
      deckName: deckName,
      deckOwnerPlayerId: deckOwnerPlayerId,
      deckOwnerName: deckOwnerName,
      anonymousLabel: anonymousLabel,
      colorIdentity: colorIdentity,
      startingLife: startingLife,
      team: team,
      startPosition: startPosition,
      placement: placement,
    );
  }
}
