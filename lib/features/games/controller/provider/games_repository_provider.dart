import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../../../database/provider/database_provider.dart';
import '../repository/games_repository.dart';

final gamesRepositoryProvider = Provider<GamesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return GamesRepository(db);
});

final recentGamesProvider = StreamProvider<List<Game>>((ref) {
  final repo = ref.watch(gamesRepositoryProvider);
  return repo.watchRecentGames();
});

/// Fuer die Partien-Uebersicht (siehe games_overview_screen.dart) -
/// wie [recentGamesProvider], aber inklusive der durchsuchbaren
/// Begriffe je Partie (Spieler/Commander/Deck), siehe GameListItem.
final gamesWithSearchTermsProvider = StreamProvider<List<GameListItem>>((
  ref,
) {
  final repo = ref.watch(gamesRepositoryProvider);
  return repo.watchGamesWithSearchTerms();
});

final gameByIdProvider = StreamProvider.family<Game?, int>((ref, gameId) {
  final repo = ref.watch(gamesRepositoryProvider);
  return repo.watchGameById(gameId);
});

final gameParticipantsProvider =
    StreamProvider.family<List<GameParticipant>, int>((ref, gameId) {
  final repo = ref.watch(gamesRepositoryProvider);
  return repo.watchParticipants(gameId);
});

final gameParticipantViewsProvider =
    StreamProvider.family<List<GameParticipantView>, int>((ref, gameId) {
  final repo = ref.watch(gamesRepositoryProvider);
  return repo.watchParticipantViews(gameId);
});

/// Abgeschlossene Partien-Teilnahmen eines Spielers (in der Praxis: des
/// Ich-Spielers) - Basis für das Statistik-Dashboard, siehe
/// GamesRepository.watchSelfGameStats.
final selfGameStatsProvider =
    StreamProvider.family<List<SelfGameStatsRow>, int>((ref, selfPlayerId) {
  final repo = ref.watch(gamesRepositoryProvider);
  return repo.watchSelfGameStats(selfPlayerId);
});
