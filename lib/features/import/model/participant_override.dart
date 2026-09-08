/// Wie ein einzelner Partie-Teilnehmer beim Import aufgelöst werden
/// soll (siehe ParticipantOverride).
enum ParticipantOverrideMode { auto, assign, anonymous }

/// Manuelle "on the fly"-Übersteuerung eines einzelnen
/// Partie-Teilnehmers beim Import (siehe ImportWizardScreen/
/// GameImportTile) - z. B. um einen per QR geteilten Teilnehmer als
/// sich selbst (oder einen anderen bereits bekannten lokalen Spieler)
/// zu erkennen und dafür ein EIGENES Deck auszuwählen (z. B. statt nur
/// der erfassten Farbidentität "WU" ein konkretes eigenes WU-Deck) -
/// unabhängig vom im Bundle erfassten `playerName`/`deckName`. Ohne
/// Übersteuerung ([mode] == auto) greift stattdessen der automatische
/// Namens-Abgleich (siehe ImportService.performImport).
class ParticipantOverride {
  final ParticipantOverrideMode mode;

  /// Nur bei mode == assign: die lokale id des Spielers, dem dieser
  /// Teilnehmer zugeordnet werden soll (der Ich-Spieler oder ein
  /// anderer bereits bekannter Spieler).
  final int? playerId;

  /// Nur bei mode == assign: die lokale id des zugeordneten Decks.
  /// Auch mit gesetztem [playerId] optional - "kein Deck angeben" ist
  /// ein gültiger Zustand.
  final int? deckId;

  const ParticipantOverride.auto()
      : mode = ParticipantOverrideMode.auto,
        playerId = null,
        deckId = null;

  const ParticipantOverride.assign({required this.playerId, this.deckId})
      : mode = ParticipantOverrideMode.assign;

  const ParticipantOverride.anonymous()
      : mode = ParticipantOverrideMode.anonymous,
        playerId = null,
        deckId = null;
}
