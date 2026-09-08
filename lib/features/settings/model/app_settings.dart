/// Globale App-Einstellungen.
///
/// [trackOtherPlayers] = false: Es wird nur der Nutzer selbst als
/// Spieler (inkl. eigener Decks) dauerhaft erfasst - reiner
/// Solo-Betrieb, keine Gruppen, keine Mitspieler-Verwaltung.
///
/// [trackOtherPlayers] = true: Zusätzlich können beliebig viele
/// Spielgruppen mit eigenen Mitgliedern und deren Decks angelegt und
/// verwaltet werden (siehe Groups/PlayerGroupMemberships).
///
/// Unabhängig von diesem Schalter können jederzeit Partien mit
/// unbekannten Spielern/Decks (nur Farbidentität) erfasst werden -
/// siehe GameParticipants.
class AppSettings {
  final bool trackOtherPlayers;
  final int? selfPlayerId;

  const AppSettings({this.trackOtherPlayers = false, this.selfPlayerId});

  AppSettings copyWith({bool? trackOtherPlayers, int? selfPlayerId}) {
    return AppSettings(
      trackOtherPlayers: trackOtherPlayers ?? this.trackOtherPlayers,
      selfPlayerId: selfPlayerId ?? this.selfPlayerId,
    );
  }
}
