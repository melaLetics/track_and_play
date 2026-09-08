import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../../../database/provider/database_provider.dart';
import '../repository/decks_repository.dart';

final decksRepositoryProvider = Provider<DecksRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DecksRepository(db);
});

final playerDecksProvider =
    StreamProvider.family<List<Deck>, int>((ref, ownerPlayerId) {
  final repo = ref.watch(decksRepositoryProvider);
  return repo.watchDecksForPlayer(ownerPlayerId);
});

/// ALLE Decks eines Spielers inkl. archivierte - für den "Archivierte
/// anzeigen"-Umschalter auf PlayerDetailScreen.
final allPlayerDecksProvider =
    StreamProvider.family<List<Deck>, int>((ref, ownerPlayerId) {
  final repo = ref.watch(decksRepositoryProvider);
  return repo.watchAllDecksForPlayer(ownerPlayerId);
});

final deckByIdProvider = StreamProvider.family<Deck?, int>((ref, deckId) {
  final repo = ref.watch(decksRepositoryProvider);
  return repo.watchDeckById(deckId);
});
