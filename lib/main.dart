import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/home/view/main_shell.dart';
import 'features/players/controller/provider/players_repository_provider.dart';
import 'features/setup/view/widgets/setup_wizard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TrackAndPlayApp()));
}

class TrackAndPlayApp extends StatelessWidget {
  const TrackAndPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Track & Play',
      debugShowCheckedModeBanner: false,
      // Bewusst nur der dunkle "Vault & Foil"-Modus, unabhängig von der
      // Geräte-Einstellung (auf Nutzerwunsch - der helle Modus wirkte im
      // Vergleich "übertrieben hell"). AppTheme.light bleibt im Code
      // erhalten, falls später doch ein Hell-Modus gewünscht wird, wird
      // hier aber nicht mehr verwendet.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const AppRoot(),
    );
  }
}

/// Entscheidet beim Start, ob der Setup-Wizard (noch kein "Ich"-Spieler
/// angelegt) oder die Hauptansicht gezeigt wird.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfPlayerAsync = ref.watch(selfPlayerProvider);

    return selfPlayerAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(child: Text('Fehler beim Laden: $error')),
      ),
      data: (selfPlayer) {
        if (selfPlayer == null) {
          return const SetupWizard();
        }
        return const MainShell();
      },
    );
  }
}
