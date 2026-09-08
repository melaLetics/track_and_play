/// Freischalt-Status EINES Badges aus dem Katalog
/// (badge_definitions.dart), berechnet für den Ich-Spieler - siehe
/// computeAchievements in achievement_engine.dart.
class AchievementStatus {
  final bool unlocked;

  /// Zeitpunkt der Freischaltung, sofern [unlocked]. Bei den meisten
  /// Badges der FRÜHESTE Erreichungszeitpunkt (z. B. "100. Partie
  /// gespielt", Farbchampion, die meisten Spezial-Badges); bei Serien
  /// (Sieg-Serien, Wochentags-Serien) bewusst der ZULETZT erreichte
  /// Zeitpunkt - 1:1 aus dem Verhalten des alten mtg_stats_tracker
  /// übernommen, siehe achievement_engine.dart für die jeweilige
  /// Begründung.
  final DateTime? achievedAt;

  /// Wie oft dieses Badge bereits erreicht wurde - NUR bei Badges, die
  /// sich wiederholt "erarbeiten" lassen (Sieg-Serien, Wochentags-
  /// Serien; siehe _computeStreaks/_computeWeekday in
  /// achievement_engine.dart), sonst null. Bei diesen beiden
  /// Kategorien zählt jede erneut erreichte Serie dieser Länge als ein
  /// weiteres Mal, auch wenn [achievedAt] (mit dem Nutzer abgestimmt,
  /// wie bisher) nur den ZULETZT erreichten Zeitpunkt zeigt.
  final int? timesAchieved;

  const AchievementStatus({
    required this.unlocked,
    this.achievedAt,
    this.timesAchieved,
  });

  static const locked = AchievementStatus(unlocked: false);
}
