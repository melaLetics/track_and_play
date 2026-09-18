import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/score_gauge.dart';
import '../../../games/controller/provider/games_repository_provider.dart';
import '../../../stats/model/player_performance_stats.dart';

/// "Dein Player-Score"-Karte im Home-Dashboard - auf Nutzerwunsch als
/// Barometer dargestellt, angelehnt an "PlayerScore"/"Speedometer"
/// aus mtg_stats_tracker (dort für einen anderen, eigenen
/// "Dominance"-Score genutzt). Nutzt hier den bereits für das
/// Statistik-Dashboard vorhandenen `computeEloScore`
/// (player_performance_stats.dart), aber bewusst UNGEFILTERT nach
/// Gruppe/Modus - analog zu den Achievements (siehe
/// achievement_engine.dart), im Unterschied zur filterbaren
/// Elo-Anzeige auf dem Statistik-Tab.
///
/// Auf Nutzerwunsch die am stärksten hervorgehobene Karte des
/// Dashboards (steht seither auch an erster Stelle, siehe
/// HomeScreen.build) - nach einem ersten, zu schlichten Versuch
/// (einfacher goldener Rand + flache Tönung) auf zweiten
/// Nutzerwunsch ("Versuche ein etwas edleres Design") bewusst
/// aufwendiger gestaltet, als "Vault-Plakette" im Look des
/// "Vault & Foil"-Themes:
/// - Gold-Rahmen als echter FARBVERLAUF statt einfarbiger Linie
///   (`BorderSide` kann keinen Gradient - stattdessen ein äußerer
///   `Container` mit Gradient-`BoxDecoration` und 1,4px Padding als
///   "Rahmendicke", der einen inneren `Container` mit dem
///   eigentlichen Karteninhalt umschließt).
/// - Inhalts-Hintergrund selbst ebenfalls ein sanfter vertikaler
///   Verlauf (`surfaceContainerHigh` → `surface`) statt einer
///   flachen Fläche, für mehr Tiefe.
/// - Warmer Gold-Schimmer als weicher `BoxShadow` um die ganze Karte
///   (großer `blurRadius`, negativer `spreadRadius`, damit er nicht
///   hart wirkt) statt der Standard-Material-Elevation-Schlagschatten.
/// - Titel in Kapitälchen-Anmutung (`letterSpacing`, Cinzel-Schrift
///   über `textTheme.titleLarge`, die laut app_theme.dart bereits
///   app-weit Cinzel führt) mit dünner Gold-Trennlinie darunter -
///   wirkt wie eine gravierte Plakette statt einer normalen
///   Karten-Überschrift.
/// - Score-Zahl selbst über den neuen optionalen
///   `ScoreGauge.scoreTextStyle`-Parameter auf `AppTheme.
///   statNumberStyle` (IBM Plex Mono, tabellarische Ziffern) statt
///   der Standard-Textschrift umgestellt - genau der Zweck, für den
///   dieser Style laut seiner eigenen Doku ursprünglich vorgesehen,
///   aber noch nirgends eingebaut war (siehe app_theme.dart). Der
///   Stats-Tab (`StatsScreen`, zweiter `ScoreGauge`-Nutzer) bleibt
///   davon unberührt, da der Parameter dort weiterhin weggelassen
///   wird.
class EloScoreCard extends ConsumerWidget {
  final int selfPlayerId;

  const EloScoreCard({required this.selfPlayerId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(selfGameStatsProvider(selfPlayerId));
    final scheme = Theme.of(context).colorScheme;

    return statsAsync.maybeWhen(
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();

        final elo = computeEloScore(rows);
        final score = elo.score0to100;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: 0.35),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          // "Rahmendicke" des Gold-Verlaufs - der innere Container
          // liegt genau um diesen Betrag eingerückt darüber.
          padding: const EdgeInsets.all(1.4),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.surfaceContainerHigh, scheme.surface],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              children: [
                Text(
                  'DEIN PLAYER-SCORE',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.primary,
                    fontSize: 18,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 56,
                  height: 1,
                  color: scheme.primary.withValues(alpha: 0.5),
                ),
                ScoreGauge(
                  score: score,
                  label: eloScoreLabel(score),
                  scoreTextStyle: AppTheme.statNumberStyle(
                    context,
                    fontSize: 40,
                  ),
                ),
                Text(
                  'Basiert auf ${elo.gamesCounted} '
                  '${elo.gamesCounted == 1 ? 'Partie' : 'Partien'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
