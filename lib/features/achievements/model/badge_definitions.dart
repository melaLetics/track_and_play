/// Statischer Katalog aller Badges/Erfolge.
///
/// Die Badge-Grafiken sind 1:1 aus mtg_stats übernommen
/// (assets/badges/...), da die Badges unbedingt erhalten bleiben sollen.
/// Die eigentliche Freischalt-Logik (wann welches Badge erreicht ist)
/// wird als nächster Schritt gegen das neue Datenmodell implementiert -
/// siehe ARCHITECTURE.md.
library;

enum BadgeCategory { streak, matches, wins, colorChampion, weekday, special }

class BadgeDefinition {
  final String id;
  final BadgeCategory category;
  final String assetPath;
  final String title;

  const BadgeDefinition({
    required this.id,
    required this.category,
    required this.assetPath,
    required this.title,
  });
}

// --- Streaks ---------------------------------------------------------
const List<int> streakThresholds = [2, 3, 5, 10];

final List<BadgeDefinition> streakBadges = [
  for (final n in streakThresholds)
    BadgeDefinition(
      id: 'streak_$n',
      category: BadgeCategory.streak,
      assetPath:
          'assets/badges/streak/${n.toString().padLeft(2, '0')}_streak.png',
      title: '$n Siege in Folge',
    ),
];

// --- Partien / Siege ---------------------------------------------------
const List<int> matchThresholds = [100, 200, 500, 1000];
const List<int> winThresholds = [10, 20, 50, 100, 200, 500, 1000];

final List<BadgeDefinition> matchBadges = [
  for (final n in matchThresholds)
    BadgeDefinition(
      id: 'matches_$n',
      category: BadgeCategory.matches,
      assetPath: 'assets/badges/matches/${n}matches.png',
      title: '$n Partien gespielt',
    ),
];

final List<BadgeDefinition> winBadges = [
  for (final n in winThresholds)
    BadgeDefinition(
      id: 'wins_$n',
      category: BadgeCategory.wins,
      assetPath: 'assets/badges/wins/${n}wins.png',
      title: '$n Siege',
    ),
];

// --- Farbchampion --------------------------------------------------
const List<String> _monoColors = ['w', 'u', 'b', 'r', 'g'];
const List<String> _monoTiers = ['', '_champ', '_master'];
const List<String> _twoColorCombos = [
  'wu', 'wb', 'wr', 'wg', 'ub', 'ug', 'ur', 'br', 'bg', 'rg',
];
const List<String> _threeColorCombos = [
  'brg', 'ubg', 'ubr', 'urg', 'wbg', 'wbr', 'wrg', 'wub', 'wug', 'wur',
];
const List<String> _fourColorCombos = [
  'ubrg', 'wbrg', 'wubg', 'wubr', 'wurg',
];

final List<BadgeDefinition> colorChampionBadges = [
  for (final c in _monoColors)
    for (final tier in _monoTiers)
      BadgeDefinition(
        id: 'color_$c$tier',
        category: BadgeCategory.colorChampion,
        assetPath: 'assets/badges/colors/mono/$c$tier.png',
        title: 'Farbchampion ${c.toUpperCase()}${tier.replaceAll('_', ' ')}',
      ),
  for (final combo in _twoColorCombos)
    BadgeDefinition(
      id: 'color_$combo',
      category: BadgeCategory.colorChampion,
      assetPath: 'assets/badges/colors/two/$combo.png',
      title: 'Farbchampion ${combo.toUpperCase()}',
    ),
  for (final combo in _threeColorCombos)
    BadgeDefinition(
      id: 'color_$combo',
      category: BadgeCategory.colorChampion,
      assetPath: 'assets/badges/colors/three/$combo.png',
      title: 'Farbchampion ${combo.toUpperCase()}',
    ),
  for (final combo in _fourColorCombos)
    BadgeDefinition(
      id: 'color_$combo',
      category: BadgeCategory.colorChampion,
      assetPath: 'assets/badges/colors/four/$combo.png',
      title: 'Farbchampion ${combo.toUpperCase()}',
    ),
  const BadgeDefinition(
    id: 'color_wubrg',
    category: BadgeCategory.colorChampion,
    assetPath: 'assets/badges/colors/wubrg.png',
    title: 'Fünffarben-Champion',
  ),
  const BadgeDefinition(
    id: 'color_n',
    category: BadgeCategory.colorChampion,
    assetPath: 'assets/badges/colors/n.png',
    title: 'Farblos-Champion',
  ),
];

// --- Wochentags-Serien -------------------------------------------------
const List<String> _weekdays = [
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
];
const List<String> _weekdayThresholds = ['02', '03', '05'];

final List<BadgeDefinition> weekdayBadges = [
  for (final day in _weekdays)
    for (final t in _weekdayThresholds)
      BadgeDefinition(
        id: 'weekday_${day}_$t',
        category: BadgeCategory.weekday,
        assetPath: 'assets/badges/weekday/$day$t.png',
        title: '$day-Serie ($t)',
      ),
];

// --- Spezial-Badges ------------------------------------------------
final List<BadgeDefinition> specialBadges = [
  const BadgeDefinition(
    id: 'first_strike',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/firstStrike.png',
    title: 'Erster Schlag',
  ),
  const BadgeDefinition(
    id: 'first_win',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/firstwin.png',
    title: 'Erster Sieg',
  ),
  const BadgeDefinition(
    id: 'grandios',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/grandios.png',
    title: 'Grandios',
  ),
  const BadgeDefinition(
    id: 'newbie',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/newbie.png',
    title: 'Newbie',
  ),
  const BadgeDefinition(
    id: 'weekend',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/weekend.png',
    title: 'Wochenend-Krieger',
  ),
  const BadgeDefinition(
    id: 'shame',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/shame.png',
    title: 'Ehrenwerte Niederlage',
  ),
  const BadgeDefinition(
    id: 'win_five_diff_decks',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/win_five_diff_decks.png',
    title: 'Sieg mit 5 verschiedenen Decks',
  ),
  const BadgeDefinition(
    id: 'win_ten_diff_decks',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/win_ten_diff_decks.png',
    title: 'Sieg mit 10 verschiedenen Decks',
  ),
  const BadgeDefinition(
    id: 'win_twentyfive_diff_decks',
    category: BadgeCategory.special,
    assetPath: 'assets/badges/special/win_twentyfive_diff_decks.png',
    title: 'Sieg mit 25 verschiedenen Decks',
  ),
];

List<BadgeDefinition> get allBadges => [
      ...streakBadges,
      ...matchBadges,
      ...winBadges,
      ...colorChampionBadges,
      ...weekdayBadges,
      ...specialBadges,
    ];
