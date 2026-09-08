import 'package:drift/drift.dart';

import '../../../../database/app_database.dart';

class DecksRepository {
  final AppDatabase db;

  DecksRepository(this.db);

  /// Nicht archivierte Decks eines Spielers, alphabetisch sortiert.
  Stream<List<Deck>> watchDecksForPlayer(int ownerPlayerId) {
    final query = db.select(db.decks)
      ..where(
        (d) => d.ownerPlayerId.equals(ownerPlayerId) & d.archived.equals(false),
      )
      ..orderBy([(d) => OrderingTerm(expression: d.name)]);
    return query.watch();
  }

  /// ALLE Decks eines Spielers (inkl. archivierte), alphabetisch
  /// sortiert - für den "Archivierte anzeigen"-Umschalter auf
  /// PlayerDetailScreen (siehe ARCHITECTURE.md). Ohne diesen Umschalter
  /// waren archivierte Decks nach dem Archivieren nirgends mehr
  /// sichtbar oder reaktivierbar.
  Stream<List<Deck>> watchAllDecksForPlayer(int ownerPlayerId) {
    final query = db.select(db.decks)
      ..where((d) => d.ownerPlayerId.equals(ownerPlayerId))
      ..orderBy([(d) => OrderingTerm(expression: d.name)]);
    return query.watch();
  }

  Future<int> createDeck({
    required int ownerPlayerId,
    required String name,
    required String colorIdentity,
    String? commanderName,
    String? secondCommanderName,
    DeckBuildType? buildType,
    int? bracket,
    bool isProxy = false,
    bool isTournamentLegal = true,
    String? deckLink,
  }) {
    return db.into(db.decks).insert(
          DecksCompanion.insert(
            ownerPlayerId: ownerPlayerId,
            name: name,
            colorIdentity: Value(colorIdentity),
            commanderName: Value(commanderName),
            secondCommanderName: Value(secondCommanderName),
            buildType: Value(buildType),
            bracket: Value(bracket),
            isProxy: Value(isProxy),
            isTournamentLegal: Value(isTournamentLegal),
            deckLink: Value(deckLink),
          ),
        );
  }

  Future<void> updateDeck(
    int deckId, {
    required String name,
    required String colorIdentity,
    String? commanderName,
    String? secondCommanderName,
    DeckBuildType? buildType,
    int? bracket,
    bool isProxy = false,
    bool isTournamentLegal = true,
    String? deckLink,
  }) {
    return (db.update(db.decks)..where((d) => d.id.equals(deckId))).write(
      DecksCompanion(
        name: Value(name),
        colorIdentity: Value(colorIdentity),
        commanderName: Value(commanderName),
        secondCommanderName: Value(secondCommanderName),
        buildType: Value(buildType),
        bracket: Value(bracket),
        isProxy: Value(isProxy),
        isTournamentLegal: Value(isTournamentLegal),
        deckLink: Value(deckLink),
      ),
    );
  }

  Future<void> setArchived(int deckId, bool archived) {
    return (db.update(db.decks)..where((d) => d.id.equals(deckId)))
        .write(DecksCompanion(archived: Value(archived)));
  }

  Stream<Deck?> watchDeckById(int deckId) {
    final query = db.select(db.decks)..where((d) => d.id.equals(deckId));
    return query.watchSingleOrNull();
  }
}
