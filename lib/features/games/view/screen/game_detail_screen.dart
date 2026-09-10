import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../../export/controller/provider/export_service_provider.dart';
import '../../../export/view/widgets/qr_share_dialog.dart';
import '../../../groups/controller/provider/groups_repository_provider.dart';
import '../../controller/provider/games_repository_provider.dart';
import '../../model/game_mode_labels.dart';
import 'live_game_screen.dart';

/// Detailansicht einer einzelnen Partie: Modus, Datum, Gruppe (falls
/// vorhanden), Dauer (bei Live-Partien), Teilnehmer mit Sieger- und
/// First-Blood-Markierung. Bei einer noch LAUFENDEN Partie (status ==
/// inProgress, z. B. nachdem der Live-Screen per Zurück-Taste
/// verlassen wurde, siehe ARCHITECTURE.md) zusätzlich zwei Aktionen
/// zum Fortsetzen oder vollständigen Verwerfen (Nutzer-Bugreport: bis
/// hierhin gab es dafür keine Möglichkeit).
class GameDetailScreen extends ConsumerWidget {
  final int gameId;

  const GameDetailScreen({super.key, required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameAsync = ref.watch(gameByIdProvider(gameId));
    final participantsAsync = ref.watch(gameParticipantViewsProvider(gameId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partie'),
        actions: [
          gameAsync.maybeWhen(
            data: (game) {
              if (game == null || game.status != GameStatus.completed) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.qr_code),
                tooltip: 'Partie teilen (QR)',
                onPressed: () async {
                  final bundle = await ref
                      .read(exportServiceProvider)
                      .buildGameQrBundle(gameId);
                  if (!context.mounted) return;
                  showQrShareDialog(
                    context,
                    title: 'Partie teilen',
                    bundle: bundle,
                  );
                },
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: gameAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
        data: (game) {
          if (game == null) {
            return const Center(child: Text('Partie nicht gefunden.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                gameModeLabels[game.mode] ?? game.mode.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${game.playedAt.day.toString().padLeft(2, '0')}.'
                '${game.playedAt.month.toString().padLeft(2, '0')}.'
                '${game.playedAt.year}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (game.groupId != null) _GroupLine(groupId: game.groupId!),
              if (game.status == GameStatus.inProgress) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Diese Partie läuft noch (nicht abgeschlossen).',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              _resumeLiveGame(context, ref, game),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Fortsetzen'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _cancelLiveGame(context, ref, game),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Abbrechen'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (game.durationSeconds != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Dauer: ${_formatDuration(game.durationSeconds!)}',
                  ),
                ),
              if (game.isDraw)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Unentschieden',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              if (game.notes != null && game.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Notizen: ${game.notes}'),
                ),
              const SizedBox(height: 24),
              Text(
                'Teilnehmer',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              participantsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (error, stack) => Text('Fehler: $error'),
                data: (participants) {
                  final sorted = [...participants]..sort((a, b) {
                    final pa = a.placement ?? 999;
                    final pb = b.placement ?? 999;
                    return pa.compareTo(pb);
                  });
                  return Column(
                    children: [
                      for (final p in sorted)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              p.isWinner
                                  ? Icons.emoji_events
                                  : Icons.person_outline,
                              color: p.isWinner
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(p.displayName),
                            subtitle: Text(
                              [
                                p.deckName ??
                                    (p.colorIdentity.isEmpty
                                        ? 'Kein Deck angegeben'
                                        : p.colorIdentity),
                                if (p.startPosition != null)
                                  'Start ${p.startPosition}',
                                if (p.placement != null) 'Platz ${p.placement}',
                                if (p.team != null && p.team!.isNotEmpty)
                                  p.team == 'archenemy'
                                      ? 'Erzfeind'
                                      : (p.team == 'team'
                                          ? 'Team'
                                          : 'Team ${p.team}'),
                              ].join(' · '),
                            ),
                            trailing: game.firstBloodParticipantId == p.id
                                ? const Chip(
                                    avatar: Icon(Icons.bloodtype, size: 18),
                                    label: Text('First Blood'),
                                  )
                                : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).remainder(60).toString().padLeft(2, '0');
    final hours = totalSeconds ~/ 3600;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds min';
  }

  /// Setzt eine laufende (noch nicht abgeschlossene) Partie im Live-Screen
  /// fort. Lädt dazu die aktuellen Teilnehmer inkl. ihres zuletzt
  /// protokollierten Lebenspunktestands aus der DB und übergibt sie an
  /// [LiveGameScreen], anstatt eine neue Partie zu starten.
  Future<void> _resumeLiveGame(
    BuildContext context,
    WidgetRef ref,
    Game game,
  ) async {
    final repo = ref.read(gamesRepositoryProvider);
    final participants = await repo.loadLiveParticipants(game.id);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveGameScreen(
          gameId: game.id,
          mode: game.mode,
          startedAt: game.startedAt ?? game.createdAt,
          participants: participants,
          firstBloodParticipantId: game.firstBloodParticipantId,
        ),
      ),
    );
  }

  /// Bricht eine laufende Partie nach Rückfrage vollständig ab: löscht die
  /// Partie inkl. aller Teilnehmer und protokollierten Lebenspunkte-
  /// Änderungen unwiderruflich aus der DB.
  Future<void> _cancelLiveGame(
    BuildContext context,
    WidgetRef ref,
    Game game,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Partie abbrechen?'),
        content: const Text(
          'Die Partie und alle bisher erfassten Lebenspunkte-Änderungen '
          'werden unwiderruflich gelöscht. Das lässt sich nicht rückgängig '
          'machen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zurück'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Partie abbrechen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(gamesRepositoryProvider);
    await repo.cancelLiveGame(game.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _GroupLine extends ConsumerWidget {
  final int groupId;

  const _GroupLine({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupByIdProvider(groupId));
    return groupAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (group) => group == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Gruppe: ${group.name}'),
            ),
    );
  }
}
