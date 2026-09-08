import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/color_identity_names.dart';
import '../../../../core/widgets/mana_symbol.dart';
import '../../../../core/widgets/score_gauge.dart';
import '../../../../database/app_database.dart';
import '../../../games/controller/provider/games_repository_provider.dart';
import '../../../games/model/game_mode_labels.dart';
import '../../../groups/controller/provider/groups_repository_provider.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import '../../../settings/controller/provider/app_settings_provider.dart';
import '../../model/player_performance_stats.dart';
import '../../model/player_stats.dart';

/// Statistik-Dashboard für den Ich-Spieler: Siegquote gesamt und nach
/// Deck/Farbidentität/Startposition/Partiendauer sowie ein Elo-artiger
/// Performance-Score, aus allen abgeschlossenen Partien-Teilnahmen
/// berechnet (siehe GamesRepository.watchSelfGameStats,
/// computePlayerStats und player_performance_stats.dart).
/// Mit dem Nutzer abgestimmter Funktionsumfang (siehe ARCHITECTURE.md):
/// global mit Umschalter auf eine bestimmte Gruppe und/oder einen
/// bestimmten Modus, nur die eigene Statistik (kein Vergleich zwischen
/// mehreren Spielern - der Elo-Score bewertet bewusst nur den
/// Ich-Spieler, keine anderen Teilnehmer).
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  /// null = "Alle Partien" (global, kein Gruppen-Filter).
  int? _selectedGroupId;

  /// null = "Alle Modi" (EDH/cEDH/2HG/Erzfeind zusammen).
  GameMode? _selectedMode;

  @override
  Widget build(BuildContext context) {
    final selfPlayerAsync = ref.watch(selfPlayerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Statistik')),
      body: selfPlayerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
        data: (self) {
          if (self == null) {
            return const Center(child: Text('Kein Spieler angelegt.'));
          }
          return _StatsBody(
            selfPlayerId: self.id,
            selectedGroupId: _selectedGroupId,
            onGroupChanged: (groupId) =>
                setState(() => _selectedGroupId = groupId),
            selectedMode: _selectedMode,
            onModeChanged: (mode) => setState(() => _selectedMode = mode),
          );
        },
      ),
    );
  }
}

class _StatsBody extends ConsumerWidget {
  final int selfPlayerId;
  final int? selectedGroupId;
  final ValueChanged<int?> onGroupChanged;
  final GameMode? selectedMode;
  final ValueChanged<GameMode?> onModeChanged;

  const _StatsBody({
    required this.selfPlayerId,
    required this.selectedGroupId,
    required this.onGroupChanged,
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(selfGameStatsProvider(selfPlayerId));
    final settingsAsync = ref.watch(settingsControllerProvider);
    final trackOtherPlayers = settingsAsync.maybeWhen(
      data: (settings) => settings.trackOtherPlayers,
      orElse: () => false,
    );
    final groupsAsync = ref.watch(allGroupsProvider);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Fehler: $error')),
      data: (rows) {
        final filtered = rows
            .where(
              (r) => selectedGroupId == null || r.groupId == selectedGroupId,
            )
            .where((r) => selectedMode == null || r.mode == selectedMode)
            .toList();
        final stats = computePlayerStats(filtered);
        final elo = computeEloScore(filtered);
        final byColor = computeWinRateByColorIdentity(filtered);
        final byPosition = computeWinRateByStartPosition(filtered);
        final byDuration = computeWinRateByDuration(filtered);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<GameMode?>(
              initialValue: selectedMode,
              decoration: const InputDecoration(labelText: 'Modus'),
              items: [
                const DropdownMenuItem<GameMode?>(
                  value: null,
                  child: Text('Alle Modi'),
                ),
                for (final mode in GameMode.values)
                  DropdownMenuItem<GameMode?>(
                    value: mode,
                    child: Text(gameModeLabels[mode] ?? mode.name),
                  ),
              ],
              onChanged: onModeChanged,
            ),
            const SizedBox(height: 12),
            if (trackOtherPlayers)
              groupsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (groups) => DropdownButtonFormField<int?>(
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(labelText: 'Gruppe'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Alle Partien'),
                    ),
                    for (final group in groups)
                      DropdownMenuItem<int?>(
                        value: group.id,
                        child: Text(group.name),
                      ),
                  ],
                  onChanged: onGroupChanged,
                ),
              ),
            if (trackOtherPlayers) const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gesamt',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${stats.gamesPlayed} '
                      '${stats.gamesPlayed == 1 ? 'Partie' : 'Partien'} - '
                      '${stats.wins} Siege',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Siegquote: ${_formatRate(stats.winRate)}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (stats.gamesPlayed > 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Score',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Center(
                        child: ScoreGauge(
                          score: elo.score0to100,
                          label: eloScoreLabel(elo.score0to100),
                        ),
                      ),
                      Text(
                        'Basiert auf ${elo.gamesCounted} '
                        '${elo.gamesCounted == 1 ? 'Partie' : 'Partien'} in '
                        'dieser Auswahl, chronologisch ausgewertet. 50 = '
                        'durchschnittlich; ohne Gegner-Bewertungen ist der '
                        'Wert eine Tendenz, keine exakte Kennzahl'
                        '${elo.gamesCounted < 10 ? ' - bei so wenigen '
                              'Partien noch wenig aussagekräftig' : ''}.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            if (stats.gamesPlayed == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Noch keine abgeschlossenen Partien in dieser Auswahl.',
                ),
              )
            else ...[
              Text(
                'Nach Deck',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              // Aufteilung Eigene Decks/Decks anderer (Nutzerwunsch) -
              // moeglich seit dem Deck-Verleih (siehe
              // SelfGameStatsRow.isOwnDeck/DeckWinStats.isOwnDeck):
              // ein Spieler kann auch ein FREMDES Deck gespielt haben.
              for (final deck in stats.byDeck.where((d) => d.isOwnDeck))
                _buildDeckCard(context, deck),
              if (stats.byDeck.any((d) => !d.isOwnDeck)) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Decks anderer',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final deck in stats.byDeck.where((d) => !d.isOwnDeck))
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Opacity(
                      opacity: 0.85,
                      child: _buildDeckCard(context, deck),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              ..._bucketSection(
                context,
                title: 'Nach Farbidentität',
                buckets: byColor,
                emptyHint: 'Keine Farbidentitäten in dieser Auswahl.',
                showManaSymbols: true,
              ),
              const SizedBox(height: 20),
              ..._bucketSection(
                context,
                title: 'Nach Startposition',
                buckets: byPosition,
                emptyHint:
                    'Keine Partien mit erfasster Startposition in dieser '
                    'Auswahl (nur bei Live-Erfassung gesetzt).',
              ),
              const SizedBox(height: 20),
              ..._bucketSection(
                context,
                title: 'Nach Partiendauer',
                buckets: byDuration,
                emptyHint:
                    'Zu wenige Partien mit erfasster Dauer für eine '
                    'sinnvolle Einteilung (nur bei Live-Erfassung gesetzt).',
              ),
            ],
          ],
        );
      },
    );
  }

  /// Baut die Card fuer ein einzelnes Deck in der "Nach Deck"-Liste -
  /// fuer eigene wie fremde Decks identisch, siehe Aufruf oben (fremde
  /// Decks werden vom Aufrufer zusaetzlich eingerueckt/abgedunkelt).
  Widget _buildDeckCard(BuildContext context, DeckWinStats deck) {
    return Card(
      child: ListTile(
        title: Text(deck.deckLabel),
        // Nur noch die Mana-Symbole statt zusaetzlich auch noch der
        // rohe WUBRG-String (Nutzerwunsch) - bei farblosen Decks zeigt
        // ManaSymbolRow bereits das eindeutige Colorless-Symbol.
        subtitle: ManaSymbolRow(colorIdentity: deck.colorIdentity, size: 24),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_formatRate(deck.winRate)),
            Text(
              '${deck.wins}/${deck.gamesPlayed}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // Erkennt, ob ein Bucket-Label eine reine WUBRG-Farbidentitaet ist
  // (fuer showManaSymbols in _bucketSection) - eigene Zeile VOR dem
  // Doc-Kommentar von _bucketSection, damit dartdoc diesen Kommentar
  // nicht versehentlich an dieses Feld statt an die Methode haengt.
  static final RegExp _wubrgOnly = RegExp(r'^[WUBRG]+$');

  /// Baut eine Überschrift + Liste von [BucketWinStats] als Cards, oder
  /// einen Hinweistext, wenn keiner der Buckets Partien enthält (z. B.
  /// weil in der aktuellen Auswahl keine Startposition erfasst wurde).
  List<Widget> _bucketSection(
    BuildContext context, {
    required String title,
    required List<BucketWinStats> buckets,
    required String emptyHint,
    bool showManaSymbols = false,
  }) {
    final withGames = buckets.where((b) => b.gamesPlayed > 0).toList();
    return [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (withGames.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            emptyHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      else
        for (final bucket in withGames)
          Card(
            child: ListTile(
              // Symbole nur, wenn das Label eine reine WUBRG-Farb-
              // identitaet ist - nicht z. B. fuer den Sammel-Bucket
              // 'Kein Deck angegeben' (siehe
              // computeWinRateByColorIdentity), der farblose Decks
              // UND Partien ganz ohne Deck-Angabe zusammenfasst und
              // sich daher nicht eindeutig als Farbe darstellen laesst.
              title: showManaSymbols && _wubrgOnly.hasMatch(bucket.label)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ManaSymbolRow(colorIdentity: bucket.label),
                        const SizedBox(width: 8),
                        // Gilden-/Keil-Name statt rohem WUBRG-String
                        // (Nutzerwunsch, z. B. "UBR" -> "Grixis") -
                        // siehe color_identity_names.dart.
                        Text(colorIdentityDisplayName(bucket.label)),
                      ],
                    )
                  : Text(bucket.label),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatRate(bucket.winRate)),
                  Text(
                    '${bucket.wins}/${bucket.gamesPlayed}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
    ];
  }

  String _formatRate(double? rate) {
    if (rate == null) return '-';
    return '${(rate * 100).round()} %';
  }
}
