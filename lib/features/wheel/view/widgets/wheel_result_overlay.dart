import 'package:flutter/material.dart';

import '../../../../core/utils/color_identity_names.dart';
import '../../../../core/utils/mana_colors.dart';
import '../../../../core/widgets/mana_symbol.dart';

/// Eigenes, prominentes Overlay fürs Drehergebnis des Wheel of Fortune
/// (Nutzer-Feedback: das bisherige, unauffällige Inline-Ergebnis unter
/// dem Rad in WheelOfFortuneDialog "gefällt nicht" - stattdessen wird
/// das Ergebnis jetzt als eigener, größerer Dialog OBEN AUF dem
/// Wheel-of-Fortune-Dialog eingeblendet, siehe
/// WheelOfFortuneDialog._showResultOverlay). Großes Farb-Icon,
/// Farbname und Aufgabentext, Hintergrund in der getroffenen
/// Mana-Farbe eingefärbt (siehe [manaColors]) - Textfarbe automatisch
/// hell/dunkel je nach Helligkeit dieser Hintergrundfarbe
/// ([ThemeData.estimateBrightnessForColor]), damit z. B. auch Weiß als
/// Hintergrund lesbar bleibt. Zeigt zusätzlich die Eskalations-Stufe
/// (1-5, siehe AppSettings.wheelTasks/wheelTasksStage2/.../
/// wheelTasksStage5 sowie WheelOfFortuneDialog._stageForSpinNumber),
/// damit nachvollziehbar bleibt, warum sich die Aufgaben im Laufe der
/// Partie verschärfen.
class WheelResultOverlay extends StatelessWidget {
  final String color;
  final String taskText;
  final int stage;

  const WheelResultOverlay({
    super.key,
    required this.color,
    required this.taskText,
    required this.stage,
  });

  @override
  Widget build(BuildContext context) {
    final tint = manaColors[color] ?? colorlessManaColor;
    final colorName = colorIdentityNames[color] ?? color;
    final onTint = ThemeData.estimateBrightnessForColor(tint) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Center(child: ManaSymbol(color: color, size: 60)),
            ),
            const SizedBox(height: 18),
            Text(
              'STUFE $stage',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: onTint.withValues(alpha: 0.75),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              colorName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: onTint,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 14),
            Text(
              taskText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: onTint,
                  ),
            ),
            const SizedBox(height: 26),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: onTint,
                foregroundColor: tint,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Weiter'),
            ),
          ],
        ),
      ),
    );
  }
}
