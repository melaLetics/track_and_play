import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../../../database/provider/database_provider.dart';
import '../repository/players_repository.dart';

final playersRepositoryProvider = Provider<PlayersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return PlayersRepository(db);
});

/// Liefert den "Ich"-Spieler, falls das Setup bereits abgeschlossen wurde.
/// Steuert in AppRoot, ob der Setup-Wizard oder die Hauptansicht gezeigt wird.
final selfPlayerProvider = FutureProvider<Player?>((ref) {
  final repo = ref.watch(playersRepositoryProvider);
  return repo.getSelf();
});

/// Alle nicht archivierten Spieler - z. B. für die Mitglied-Auswahl in
/// der Gruppen-Verwaltung.
final allActivePlayersProvider = StreamProvider<List<Player>>((ref) {
  final repo = ref.watch(playersRepositoryProvider);
  return repo.watchAllActive();
});

/// ALLE Spieler inkl. archivierte - für den "Archivierte anzeigen"-
/// Umschalter im "Mitglied hinzufügen"-Dialog (siehe
/// GroupDetailScreen/ARCHITECTURE.md). Da es keine eigene
/// Spielerübersicht gibt, ist das der einzige Weg, einen archivierten
/// Spieler wiederzufinden, der aktuell in KEINER Gruppe mehr Mitglied
/// ist - erneutes Hinzufügen macht ihn wieder über die Gruppen-
/// Mitgliederliste erreichbar (dort mit "(archiviert)" markiert),
/// reaktivieren lässt er sich dann auf seinem PlayerDetailScreen.
final allPlayersIncludingArchivedProvider =
    StreamProvider<List<Player>>((ref) {
  final repo = ref.watch(playersRepositoryProvider);
  return repo.watchAll();
});

/// Ein einzelner Spieler nach id (z. B. für PlayerDetailScreen).
final playerByIdProvider =
    StreamProvider.family<Player?, int>((ref, playerId) {
  final repo = ref.watch(playersRepositoryProvider);
  return repo.watchPlayerById(playerId);
});
