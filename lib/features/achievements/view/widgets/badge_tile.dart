import 'package:flutter/material.dart';

import '../../model/badge_definitions.dart';

/// Ein einzelnes Badge-Icon mit Tooltip (Name + Freischalt-Datum bzw.
/// "Noch nicht freigeschaltet"). Aus achievements_screen.dart
/// herausgezogen, damit die neue "Deine letzten Erfolge"-Karte im
/// Home-Dashboard (last_achievements_card.dart) dieselbe Optik nutzen
/// kann, statt sie zu duplizieren. Größe auf Nutzer-Feedback ("in
/// Summe etwas größer") von 48 auf 64 angehoben - wirkt an beiden
/// Stellen (Home-Dashboard-Vorschau UND Erfolge-Übersicht), da beide
/// dieselbe Komponente nutzen. Zum Vergleich: der mtg_stats_tracker-
/// Vorgänger nutzte 70 (kreisrund statt eckig) - 64 als moderater
/// Mittelweg, siehe ARCHITECTURE.md.
///
/// Sichtbare Beschriftung unter der Kachel (statt nur im Tooltip),
/// zweistufig auf Nutzerwunsch ergänzt (siehe ARCHITECTURE.md):
/// - Bezeichnung (Titel): nur bei den SPEZIAL-Badges
///   (BadgeCategory.special) - dort gibt es vergleichsweise wenige
///   Einträge. Wird auch bei gesperrten Spezial-Badges gezeigt, damit
///   erkennbar ist, was es noch zu erreichen gibt. Bei den übrigen
///   Kategorien (Serien, Partien, Siege, Farbchampion, Wochentag) gibt
///   es je Kategorie deutlich mehr Badges - ein Titel unter jeder
///   Kachel würde das Grid dort stark aufblähen, der Tooltip liefert
///   ihn bei Bedarf weiterhin.
/// - Freischalt-Datum: bei ALLEN Kategorien, sobald [unlocked] und
///   [achievedAt] gesetzt sind ("das Datum des zum letzten Mal
///   Erreichens" - bei Serien-Badges ist [achievedAt] bereits der
///   ZULETZT erreichte Zeitpunkt, siehe achievement_status.dart).
///   Gesperrte Badges zeigen kein Datum (es gibt keins).
/// - Anzahl: nur wenn [timesAchieved] gesetzt ist - das ist NUR bei
///   Sieg-Serien und Wochentags-Serien der Fall (siehe
///   AchievementStatus.timesAchieved), da sich ausschließlich diese
///   Badges wiederholt "erarbeiten" lassen (Nutzeranforderung).
class BadgeTile extends StatelessWidget {
  final BadgeDefinition badge;
  final DateTime? achievedAt;
  final bool unlocked;
  final int? timesAchieved;

  const BadgeTile({
    required this.badge,
    this.achievedAt,
    this.unlocked = true,
    this.timesAchieved,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final message = unlocked && achievedAt != null
        ? '${badge.title}\nFreigeschaltet am ${_formatDate(achievedAt!)}'
            '${timesAchieved != null ? ' ($timesAchieved\u00d7 erreicht)' : ''}'
        : '${badge.title}\nNoch nicht freigeschaltet';

    final icon = Tooltip(
      message: message,
      child: Opacity(
        opacity: unlocked ? 1.0 : 0.25,
        child: Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Image.asset(badge.assetPath, fit: BoxFit.contain),
        ),
      ),
    );

    final showTitle = badge.category == BadgeCategory.special;
    final showDate = unlocked && achievedAt != null;
    final showCount = unlocked && timesAchieved != null;
    if (!showTitle && !showDate && !showCount) {
      return icon;
    }

    final theme = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        icon,
        const SizedBox(height: 4),
        if (showTitle)
          Text(
            badge.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: unlocked ? null : theme.disabledColor,
            ),
          ),
        if (showDate)
          Text(
            _formatDate(achievedAt!),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurface),
          ),
        if (showCount)
          Text(
            '$timesAchieved× erreicht',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurface),
          ),
      ],
    );

    return showTitle ? SizedBox(width: 96, child: content) : content;
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }
}
