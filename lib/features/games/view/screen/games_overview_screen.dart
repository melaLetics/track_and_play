import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../controller/provider/games_repository_provider.dart';
import '../../model/game_mode_labels.dart';
import 'game_detail_screen.dart';
import 'game_setup_screen.dart';

/// Historie aller erfassten Partien (manuell nachgetragen oder live
/// gespielt), neueste zuerst.
class GamesOverviewScreen extends ConsumerWidget {
  const GamesOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(recentGamesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Partien')),
      body: gamesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
        data: (games) {
          if (games.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Partie erfasst.\n'
                  'Tippe unten rechts auf "+", um deine erste Partie '
                  'anzulegen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: games.length,
            itemBuilder: (context, index) => _GameListTile(game: games[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const GameSetupScreen()),
          );
        },
        tooltip: 'Neue Partie',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _GameListTile extends StatelessWidget {
  final Game game;

  const _GameListTile({required this.game});

  @override
  Widget build(BuildContext context) {
    final inProgress = game.status == GameStatus.inProgress;
    return ListTile(
      leading: Icon(
        inProgress ? Icons.play_circle_outline : Icons.check_circle_outline,
        color: inProgress ? Colors.orange : Colors.green,
      ),
      title: Text(gameModeLabels[game.mode] ?? game.mode.name),
      subtitle: Text(
        '${game.playedAt.day.toString().padLeft(2, '0')}.'
        '${game.playedAt.month.toString().padLeft(2, '0')}.'
        '${game.playedAt.year}'
        '${inProgress ? ' · läuft noch' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GameDetailScreen(gameId: game.id),
          ),
        );
      },
    );
  }
}
