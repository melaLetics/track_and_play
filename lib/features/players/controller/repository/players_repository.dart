import 'package:drift/drift.dart';

import '../../../../database/app_database.dart';

class PlayersRepository {
  final AppDatabase db;

  PlayersRepository(this.db);

  Stream<List<Player>> watchAll() => db.select(db.players).watch();

  /// Alle nicht archivierten Spieler - Basis für Auswahllisten
  /// (z. B. "Mitglied zu Gruppe hinzufügen").
  Stream<List<Player>> watchAllActive() {
    final query = db.select(db.players)..where((p) => p.archived.equals(false));
    return query.watch();
  }

  Stream<Player?> watchPlayerById(int playerId) {
    final query = db.select(db.players)..where((p) => p.id.equals(playerId));
    return query.watchSingleOrNull();
  }

  Future<Player?> getSelf() {
    final query = db.select(db.players)..where((p) => p.isSelf.equals(true));
    return query.getSingleOrNull();
  }

  /// Legt den "Ich"-Spieler an. Wird einmalig im Setup-Wizard aufgerufen.
  Future<int> createSelf(String name) {
    return db.into(db.players).insert(
          PlayersCompanion.insert(name: name, isSelf: const Value(true)),
        );
  }

  Future<int> createPlayer(String name) {
    return db.into(db.players).insert(
          PlayersCompanion.insert(name: name),
        );
  }

  Future<void> renamePlayer(int playerId, String name) {
    return (db.update(db.players)..where((p) => p.id.equals(playerId)))
        .write(PlayersCompanion(name: Value(name)));
  }

  /// Archiviert einen Spieler. Wird bewusst nicht für den Self-Player
  /// angeboten (siehe PlayerDetailScreen) - die App geht sonst von
  /// einem stets existierenden, aktiven Self-Player aus.
  Future<void> setArchived(int playerId, bool archived) {
    return (db.update(db.players)..where((p) => p.id.equals(playerId)))
        .write(PlayersCompanion(archived: Value(archived)));
  }
}
