import '../../../database/app_database.dart';

/// Laufzeit-Ansicht eines Teilnehmers während einer Live-Partie.
/// Die fortlaufenden Lebenspunkte-Änderungen werden separat als
/// LifeEvents persistiert - dies hier ist nur der initiale Zustand,
/// mit dem der Live-Screen startet. [team]/[startPosition] werden
/// unverändert aus dem Setup-Screen übernommen und beim Beenden der
/// Partie für die Platzierungsregeln (siehe game_setup_validator.dart)
/// wiederverwendet. [tableSide] bestimmt Position/Drehung der Kachel
/// im Live-Grid (siehe _LifeGrid in live_game_screen.dart) - fällt bei
/// alten, vor Einführung dieses Felds gestarteten Partien auf null
/// zurück und wird dann in der Anzeige wie "unten" (unrotiert)
/// behandelt.
class LiveParticipant {
  final int gameParticipantId;
  final String displayName;
  final int startingLife;
  final String? team;
  final int? startPosition;
  final TableSide? tableSide;

  const LiveParticipant({
    required this.gameParticipantId,
    required this.displayName,
    required this.startingLife,
    this.team,
    this.startPosition,
    this.tableSide,
  });
}
