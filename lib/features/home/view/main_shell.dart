import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../games/view/screen/games_overview_screen.dart';
import '../../players/controller/provider/players_repository_provider.dart';
import '../../players/view/screen/player_detail_screen.dart';
import '../../stats/view/screen/stats_screen.dart';
import 'home_screen.dart';

/// Haupt-Navigations-Rahmen mit Bottom Navigation Bar, auf Nutzerwunsch
/// angelehnt an mtg_stats_tracker (dort: Startseite/Decks/Spieler/
/// Partien/Optionen als schwebende, abgerundete Nav-Bar) - siehe
/// ARCHITECTURE.md "Bekannte Fixes" für die mit dem Nutzer abgestimmte
/// Tab-Auswahl. Vier Tabs statt fünf, da Track & Play weder einen
/// eigenen "Spieler"-Überblick noch einen Optionen-Screen hat: Home
/// (Begrüßung + Erfolge/Export/Import/Gruppen als Aktionen, siehe
/// [HomeScreen]), Decks (eigene Deck-Verwaltung, [PlayerDetailScreen]
/// für den Ich-Spieler), Statistik ([StatsScreen]), Partien
/// ([GamesOverviewScreen] - Historie samt "+"-Button dort für "Neue
/// Partie erfassen", kein zusätzlicher Einstieg nötig).
///
/// Jeder Tab bleibt ein vollständig eigenständiger Screen mit eigenem
/// `Scaffold`/`AppBar` statt eines gemeinsamen Shell-AppBars - so
/// funktionieren [PlayerDetailScreen] und [StatsScreen] unverändert
/// weiter, wenn sie (wie bisher) auch von ANDEREN Stellen aus einzeln
/// gepusht werden (z. B. ein Gruppenmitglied in der Gruppen-
/// Detailansicht antippen). `IndexedStack` hält alle vier Tabs am
/// Leben, damit z. B. der Scroll-Zustand der Partien-Historie beim
/// Tab-Wechsel erhalten bleibt.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final selfPlayerAsync = ref.watch(selfPlayerProvider);

    final decksTab = selfPlayerAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(child: Text('Fehler beim Laden: $error')),
      ),
      data: (self) => self == null
          ? const Scaffold(body: Center(child: Text('Kein Spieler angelegt.')))
          : PlayerDetailScreen(playerId: self.id),
    );

    final pages = <Widget>[
      const HomeScreen(),
      decksTab,
      const StatsScreen(),
      const GamesOverviewScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _VaultBottomNav(
        currentIndex: _index,
        onTap: (index) => setState(() => _index = index),
      ),
    );
  }
}

/// Schwebende, abgerundete Bottom-Nav-Bar im "Vault & Foil"-Look -
/// visuell an mtg_stats_tracker angelehnt (abgerundete Kapsel-Form,
/// Schatten, Akzentfarbe für den aktiven Tab), aber in den Theme-Farben
/// von Track & Play (siehe app_theme.dart) statt fest verdrahteter
/// Farben.
class _VaultBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _VaultBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: scheme.primary,
          unselectedItemColor: scheme.onSurface.withValues(alpha: 0.55),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.style_outlined),
              activeIcon: Icon(Icons.style),
              label: 'Decks',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: 'Statistik',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.casino_outlined),
              activeIcon: Icon(Icons.casino),
              label: 'Partien',
            ),
          ],
        ),
      ),
    );
  }
}
