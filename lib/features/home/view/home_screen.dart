import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../export/view/screen/export_wizard_screen.dart';
import '../../groups/view/screen/groups_overview_screen.dart';
import '../../import/view/screen/import_wizard_screen.dart';
import '../../players/controller/provider/players_repository_provider.dart';
import '../../settings/controller/provider/app_settings_provider.dart';
import 'widgets/elo_score_card.dart';
import 'widgets/last_achievements_card.dart';
import 'widgets/last_game_reminder_card.dart';
import 'widgets/random_deck_card.dart';

/// Home-Tab der Bottom Navigation (siehe [MainShell] in main_shell.dart):
/// ein kleines Gamification-Dashboard, auf Nutzerwunsch angelehnt an
/// den Homescreen von mtg_stats_tracker (Begrüßung, Erinnerung an die
/// letzte Partie, Random-Deck-Funktion, Elo-Score-Barometer, letzte
/// Erfolge) plus die Aktionen, die (noch) keinen eigenen Tab haben
/// (Export/Import, Gruppen-Verwaltung, "Weitere Optionen"-Card). "Neue
/// Partie erfassen"/"Partien-Historie" (jetzt Tab "Partien"), "Meine
/// Statistik" (Tab "Statistik") und "Meine Decks" (Tab "Decks") sind
/// seit Einführung der Bottom Navigation eigene Tabs; der frühere
/// eigenständige "Meine Erfolge"-Button ist mit Einführung der "Deine
/// letzten Erfolge"-Karte entfallen, die denselben Zugang über ihren
/// "Alle anzeigen"-Link bietet - siehe ARCHITECTURE.md "Bekannte
/// Fixes". Weitere mtg_stats-Dashboard-Karten (Winrate/Win-Streak/
/// Usual-Suspects/Backup-Reminder) weiterhin NICHT übernommen, da vom
/// Nutzer nicht angefordert - siehe "Noch zu bauen".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfPlayerAsync = ref.watch(selfPlayerProvider);

    return Scaffold(
      appBar: AppBar(
        // Logo + Schriftzug im Header (auf Nutzerwunsch, angelehnt an
        // mtg_stats_tracker). Gold-Farbe UND Größe (30) kommen jetzt
        // app-weit aus AppBarTheme.titleTextStyle (siehe app_theme.dart),
        // gelten also automatisch auch hier - kein lokales Override mehr
        // nötig. toolbarHeight bleibt erhöht (Standard 56), damit neben
        // dem 48px-Logo weiterhin genug vertikaler Raum ist.
        toolbarHeight: 76,
        // Row selbst kann nicht const sein - Image.asset(...) ist kein
        // const-Konstruktor (lädt das Asset zur Laufzeit).
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Image(image: AssetImage('assets/icon/tap_icon_fg.png'), height: 48),
            SizedBox(width: 12),
            Text('Track & Play'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            selfPlayerAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Text(
                'Fehler beim Laden: $error',
                textAlign: TextAlign.center,
              ),
              data: (self) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  self == null
                      ? 'Kein Spieler angelegt.'
                      : 'Willkommen zurück, ${self.name}!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            selfPlayerAsync.maybeWhen(
              data: (self) {
                if (self == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    LastGameReminderCard(selfPlayerId: self.id),
                    const SizedBox(height: 16),
                    RandomDeckCard(selfPlayerId: self.id),
                    const SizedBox(height: 16),
                    EloScoreCard(selfPlayerId: self.id),
                    const SizedBox(height: 16),
                    LastAchievementsCard(selfPlayerId: self.id),
                  ],
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            const _QuickLinksCard(),
          ],
        ),
      ),
    );
  }
}

/// Kompakte Karte "Weitere Optionen" (Export/Import/Gruppen-Verwaltung)
/// unten auf dem Home-Dashboard - auf Nutzerwunsch anstelle von drei
/// einzelnen breiten Buttons, siehe ARCHITECTURE.md "Bekannte Fixes".
class _QuickLinksCard extends ConsumerWidget {
  const _QuickLinksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final trackOtherPlayers = settingsAsync.maybeWhen(
      data: (settings) => settings.trackOtherPlayers,
      orElse: () => false,
    );

    final items = [
      if (trackOtherPlayers)
        _QuickLinkItem(
          icon: Icons.groups,
          label: 'Gruppen verwalten',
          builder: (_) => const GroupsOverviewScreen(),
        ),
      _QuickLinkItem(
        icon: Icons.ios_share,
        label: 'Daten exportieren',
        builder: (_) => const ExportWizardScreen(),
      ),
      _QuickLinkItem(
        icon: Icons.file_download,
        label: 'Daten importieren',
        builder: (_) => const ImportWizardScreen(),
      ),
    ];

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Weitere Optionen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final item in items) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: item.builder));
              },
            ),
          ],
          const Divider(height: 1),
          // Nachgerüstete Einstellung (Nutzerfrage: der Setup-Wizard
          // verspricht "später jederzeit in den Einstellungen
          // ändern", es gab dafür aber noch keine UI) - siehe
          // ARCHITECTURE.md "Bekannte Fixes". Rein additiv: bestehende
          // Gruppen/Mitspieler-Daten bleiben beim Ausschalten
          // erhalten, nur die zugehörigen UI-Bereiche verschwinden.
          SwitchListTile(
            secondary: const Icon(Icons.people_outline),
            title: const Text('Mitspieler tracken'),
            subtitle: const Text(
              'Partien mit anderen Spielern und Gruppen erfassen',
            ),
            value: trackOtherPlayers,
            onChanged: (value) {
              ref
                  .read(settingsControllerProvider.notifier)
                  .setTrackOtherPlayers(value);
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _QuickLinkItem {
  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  const _QuickLinkItem({
    required this.icon,
    required this.label,
    required this.builder,
  });
}
