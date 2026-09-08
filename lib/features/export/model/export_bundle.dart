/// Austauschformat für Export/Import (Datei UND QR-Code, siehe
/// lib/features/export/ und lib/features/import/).
///
/// Bewusst NICHT auf den lokalen Drift-Autoincrement-IDs aufgebaut, da
/// diese nur innerhalb der eigenen Datenbank gültig sind und beim
/// Import auf einem anderen Gerät nichts Sinnvolles referenzieren
/// würden. Stattdessen referenzieren alle Verknüpfungen innerhalb
/// eines Bundles per Name (Spieler-/Deck-Name) - siehe ImportService
/// für die Auflösung dieser Namen beim Import (inkl. des mit dem
/// Nutzer abgestimmten automatischen Namens-Abgleichs zur
/// Duplikat-Erkennung).
///
/// Ein "QR-Bundle" (einzelnes Deck oder einzelner Spieler, siehe
/// ExportService.buildDeckQrBundle/buildPlayerQrBundle) ist einfach
/// ein ExportBundle mit nur einem einzigen Eintrag in genau einer
/// Liste - Export/Import-Logik und -Format sind für Datei und QR
/// dieselben.
class ExportBundle {
  final int schemaVersion;
  final DateTime exportedAt;
  final List<PlayerExport> players;
  final List<DeckExport> decks;
  final List<GroupExport> groups;
  final List<GameExport> games;

  const ExportBundle({
    this.schemaVersion = 1,
    required this.exportedAt,
    this.players = const [],
    this.decks = const [],
    this.groups = const [],
    this.games = const [],
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'players': players.map((p) => p.toJson()).toList(),
        'decks': decks.map((d) => d.toJson()).toList(),
        'groups': groups.map((g) => g.toJson()).toList(),
        'games': games.map((g) => g.toJson()).toList(),
      };

  /// Wirft eine [FormatException] bei unbekanntem/zu neuem
  /// schemaVersion oder fehlerhafter Struktur - siehe
  /// ImportService.parseBundle für die nutzerfreundliche Fehlermeldung.
  factory ExportBundle.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    if (schemaVersion > 1) {
      throw FormatException(
        'Unbekannte Bundle-Version $schemaVersion - diese Datei/dieser '
        'QR-Code stammt vermutlich von einer neueren App-Version.',
      );
    }
    return ExportBundle(
      schemaVersion: schemaVersion,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      players: [
        for (final p in (json['players'] as List? ?? const []))
          PlayerExport.fromJson(p as Map<String, dynamic>),
      ],
      decks: [
        for (final d in (json['decks'] as List? ?? const []))
          DeckExport.fromJson(d as Map<String, dynamic>),
      ],
      groups: [
        for (final g in (json['groups'] as List? ?? const []))
          GroupExport.fromJson(g as Map<String, dynamic>),
      ],
      games: [
        for (final g in (json['games'] as List? ?? const []))
          GameExport.fromJson(g as Map<String, dynamic>),
      ],
    );
  }
}

/// Ein Spieler im Bundle. isSelf wird bewusst NICHT mit exportiert:
/// Jedes Zielgerät hat bereits genau seinen eigenen Self-Player (siehe
/// Players-Tabelle) - ein importierter Spieler wird daher immer als
/// normaler bekannter Spieler angelegt (siehe ImportService). Wird der
/// Ich-Spieler des Absenders mit demselben Namen wie der eigene
/// Self-Player benannt, greift beim Import der automatische
/// Namens-Abgleich ganz von selbst (siehe ImportService.buildPreview) -
/// Decks/Partien dieses Spielers landen dann korrekt beim eigenen
/// Self-Player statt bei einem doppelten Eintrag.
class PlayerExport {
  final String name;
  final bool archived;

  const PlayerExport({required this.name, this.archived = false});

  Map<String, dynamic> toJson() => {'name': name, 'archived': archived};

  factory PlayerExport.fromJson(Map<String, dynamic> json) => PlayerExport(
        name: json['name'] as String,
        archived: json['archived'] as bool? ?? false,
      );
}

/// Ein Deck im Bundle. [ownerName] referenziert einen Spieler per Name
/// (siehe Klassendokumentation oben) statt per id.
class DeckExport {
  final String ownerName;
  final String name;
  final String colorIdentity;
  final String? commanderName;
  final String? secondCommanderName;

  /// Name eines DeckBuildType-Werts (z. B. "precon"), siehe
  /// decks_table.dart - als String statt Enum, damit dieses Modell
  /// unabhängig von app_database.dart bleibt.
  final String? buildType;
  final int? bracket;
  final bool isProxy;
  final bool isTournamentLegal;
  final String? deckLink;
  final bool archived;

  const DeckExport({
    required this.ownerName,
    required this.name,
    this.colorIdentity = '',
    this.commanderName,
    this.secondCommanderName,
    this.buildType,
    this.bracket,
    this.isProxy = false,
    this.isTournamentLegal = true,
    this.deckLink,
    this.archived = false,
  });

  Map<String, dynamic> toJson() => {
        'ownerName': ownerName,
        'name': name,
        'colorIdentity': colorIdentity,
        'commanderName': commanderName,
        'secondCommanderName': secondCommanderName,
        'buildType': buildType,
        'bracket': bracket,
        'isProxy': isProxy,
        'isTournamentLegal': isTournamentLegal,
        'deckLink': deckLink,
        'archived': archived,
      };

  factory DeckExport.fromJson(Map<String, dynamic> json) => DeckExport(
        ownerName: json['ownerName'] as String,
        name: json['name'] as String,
        colorIdentity: json['colorIdentity'] as String? ?? '',
        commanderName: json['commanderName'] as String?,
        secondCommanderName: json['secondCommanderName'] as String?,
        buildType: json['buildType'] as String?,
        bracket: json['bracket'] as int?,
        isProxy: json['isProxy'] as bool? ?? false,
        isTournamentLegal: json['isTournamentLegal'] as bool? ?? true,
        deckLink: json['deckLink'] as String?,
        archived: json['archived'] as bool? ?? false,
      );
}

/// Eine Gruppe im Bundle. [memberNames] referenziert ihre Mitglieder
/// per Spieler-Name (siehe Klassendokumentation oben).
class GroupExport {
  final String name;
  final bool archived;
  final List<String> memberNames;

  const GroupExport({
    required this.name,
    this.archived = false,
    this.memberNames = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'archived': archived,
        'memberNames': memberNames,
      };

  factory GroupExport.fromJson(Map<String, dynamic> json) => GroupExport(
        name: json['name'] as String,
        archived: json['archived'] as bool? ?? false,
        memberNames: [
          for (final n in (json['memberNames'] as List? ?? const []))
            n as String,
        ],
      );
}

/// Ein Teilnehmer-Sitzplatz innerhalb eines [GameExport]. Entweder
/// bekannt ([playerName] gesetzt, optional [deckName]) oder anonym
/// ([anonymousLabel]/[anonymousColorIdentity] gesetzt) - siehe
/// GameParticipants-Tabelle, dieselbe Unterscheidung. [isWinner] und
/// [placement] werden BEIDE unverändert aus der Quelldatenbank
/// übernommen (nicht aus placement abgeleitet), damit auch
/// Team-Modi (2HG/Erzfeind) verlustfrei übertragen werden.
///
/// [colorIdentity] wird IMMER gesetzt (bei bekannten Teilnehmern vom
/// verknüpften Deck übernommen, bei anonymen von
/// [anonymousColorIdentity]) - unabhängig davon, ob das zugehörige
/// Deck selbst mit im Bundle enthalten ist. Das ermöglicht beim Import
/// die "on the fly"-Zuordnung eines Teilnehmers zu einem bereits
/// bekannten lokalen Spieler samt Auswahl eines passenden EIGENEN
/// Decks (siehe ImportService/ParticipantOverride), auch wenn nur eine
/// einzelne Partie (z. B. per QR) geteilt wurde, ohne die komplette
/// Deck-Bibliothek mitzuschicken.
///
/// [deckOwnerName] referenziert (wie [playerName]/[deckName]) einen
/// Spieler per Name und ist nur bei einem GELIEHENEN Deck gesetzt
/// (siehe AddKnownParticipantDialog/SelectDeckDialog, Deck-Verleih) -
/// [deckName] bezeichnet dann weiterhin das gespielte Deck, aber
/// dessen tatsächlicher Besitzer ist [deckOwnerName] statt
/// [playerName]. Bleibt es null, gehört das Deck (wie im Normalfall)
/// dem Teilnehmer selbst.
class GameParticipantExport {
  final String? playerName;
  final String? deckName;
  final String? deckOwnerName;
  final String? anonymousLabel;
  final String? anonymousColorIdentity;
  final String colorIdentity;
  final bool isWinner;
  final int? placement;
  final String? team;
  final int? startingLife;
  final int? startPosition;

  const GameParticipantExport({
    this.playerName,
    this.deckName,
    this.deckOwnerName,
    this.anonymousLabel,
    this.anonymousColorIdentity,
    this.colorIdentity = '',
    this.isWinner = false,
    this.placement,
    this.team,
    this.startingLife,
    this.startPosition,
  });

  Map<String, dynamic> toJson() => {
        'playerName': playerName,
        'deckName': deckName,
        'deckOwnerName': deckOwnerName,
        'anonymousLabel': anonymousLabel,
        'anonymousColorIdentity': anonymousColorIdentity,
        'colorIdentity': colorIdentity,
        'isWinner': isWinner,
        'placement': placement,
        'team': team,
        'startingLife': startingLife,
        'startPosition': startPosition,
      };

  factory GameParticipantExport.fromJson(Map<String, dynamic> json) =>
      GameParticipantExport(
        playerName: json['playerName'] as String?,
        deckName: json['deckName'] as String?,
        deckOwnerName: json['deckOwnerName'] as String?,
        anonymousLabel: json['anonymousLabel'] as String?,
        anonymousColorIdentity: json['anonymousColorIdentity'] as String?,
        colorIdentity: json['colorIdentity'] as String? ?? '',
        isWinner: json['isWinner'] as bool? ?? false,
        placement: json['placement'] as int?,
        team: json['team'] as String?,
        startingLife: json['startingLife'] as int?,
        startPosition: json['startPosition'] as int?,
      );
}

/// Eine abgeschlossene Partie im Bundle. Nur abgeschlossene Partien
/// werden je exportiert (siehe ExportService) - eine gerade laufende
/// Live-Partie auf einem anderen Gerät zu teilen ergibt keinen Sinn.
/// [mode]/[entryMode] als String (Enum-Name), siehe [DeckExport.buildType].
class GameExport {
  final DateTime playedAt;
  final String mode;
  final String? notes;
  final String? groupName;
  final String entryMode;
  final int? durationSeconds;
  final bool isDraw;
  final List<GameParticipantExport> participants;

  /// Index in [participants] des Teilnehmers, der zuerst Lebenspunkte
  /// verloren hat ("First Blood") - siehe Games.firstBloodParticipantId,
  /// hier als bundle-lokaler Index statt als (nur lokal gültige) id.
  final int? firstBloodParticipantIndex;

  const GameExport({
    required this.playedAt,
    required this.mode,
    this.notes,
    this.groupName,
    required this.entryMode,
    this.durationSeconds,
    this.isDraw = false,
    this.participants = const [],
    this.firstBloodParticipantIndex,
  });

  Map<String, dynamic> toJson() => {
        'playedAt': playedAt.toIso8601String(),
        'mode': mode,
        'notes': notes,
        'groupName': groupName,
        'entryMode': entryMode,
        'durationSeconds': durationSeconds,
        'isDraw': isDraw,
        'participants': participants.map((p) => p.toJson()).toList(),
        'firstBloodParticipantIndex': firstBloodParticipantIndex,
      };

  factory GameExport.fromJson(Map<String, dynamic> json) => GameExport(
        playedAt: DateTime.parse(json['playedAt'] as String),
        mode: json['mode'] as String,
        notes: json['notes'] as String?,
        groupName: json['groupName'] as String?,
        entryMode: json['entryMode'] as String? ?? 'manual',
        durationSeconds: json['durationSeconds'] as int?,
        isDraw: json['isDraw'] as bool? ?? false,
        participants: [
          for (final p in (json['participants'] as List? ?? const []))
            GameParticipantExport.fromJson(p as Map<String, dynamic>),
        ],
        firstBloodParticipantIndex:
            json['firstBloodParticipantIndex'] as int?,
      );
}
