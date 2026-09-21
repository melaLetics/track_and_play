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

  /// Commander/Partner-Commander des verknüpften Decks (Decks.
  /// commanderName/secondCommanderName), sofern ein Deck verknüpft ist
  /// und dort einer hinterlegt wurde - Grundlage für die
  /// Commander-Schaden-Auswahl (siehe live_game_screen.dart,
  /// Nutzerwunsch). Bei anonymen Teilnehmern oder Decks ohne
  /// hinterlegten Commander bleibt [commanderName] null; die
  /// Commander-Schaden-Auswahl zeigt dann einen generischen
  /// Platzhalter statt den Teilnehmer ganz auszuschließen.
  final String? commanderName;
  final String? secondCommanderName;

  const LiveParticipant({
    required this.gameParticipantId,
    required this.displayName,
    required this.startingLife,
    this.team,
    this.startPosition,
    this.tableSide,
    this.commanderName,
    this.secondCommanderName,
  });
}

/// Eindeutiger Schlüssel für den Commander-Schaden-Stand EINER
/// Kombination aus Empfänger, Quelle und Commander-Slot (siehe
/// CommanderDamageEvents) - als einfacher String-Key statt einer
/// eigenen Klasse mit ==/hashCode, analog zu den bereits an mehreren
/// Stellen (z. B. ImportService.deckIdByKey) verwendeten
/// zusammengesetzten String-Keys. Zentral hier definiert, damit
/// GamesRepository (Laden/Speichern) und live_game_screen.dart
/// (UI-Zustand) exakt dasselbe Format verwenden.
String commanderDamageKey({
  required int receiverId,
  required int sourceParticipantId,
  required CommanderSlot slot,
}) =>
    '$receiverId|$sourceParticipantId|${slot.name}';
