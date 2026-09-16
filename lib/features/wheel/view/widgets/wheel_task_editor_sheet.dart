import 'package:flutter/material.dart';

import '../../../../core/utils/color_identity_names.dart';
import '../../../../core/widgets/mana_symbol.dart';
import '../../model/wheel_task_suggestion.dart';

/// Bottom Sheet zum Bearbeiten der Aufgabe EINER WUBRG-Farbe (siehe
/// WheelTasksScreen) - freies Textfeld plus antippbare
/// Vorschlags-Chips (siehe [wheelTaskSuggestions], Nutzerwunsch: "ein
/// paar Optionen vorschlagen"). Ein Chip übernimmt seinen Text nur ins
/// Feld, das Ergebnis bleibt danach frei editierbar. Gibt bei
/// "Speichern" den finalen Text zurück (`Navigator.pop<String>`),
/// bei "Abbrechen"/Wegwischen null.
class WheelTaskEditorSheet extends StatefulWidget {
  final String color;
  final String initialText;

  /// Eskalations-Stufe (1-3), für die hier gerade eine Aufgabe
  /// bearbeitet wird - rein informativ im Titel angezeigt, siehe
  /// WheelTasksScreen.
  final int stage;

  const WheelTaskEditorSheet({
    super.key,
    required this.color,
    required this.initialText,
    this.stage = 1,
  });

  @override
  State<WheelTaskEditorSheet> createState() => _WheelTaskEditorSheetState();
}

class _WheelTaskEditorSheetState extends State<WheelTaskEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applySuggestion(WheelTaskSuggestion suggestion) {
    setState(() => _controller.text = suggestion.text);
  }

  @override
  Widget build(BuildContext context) {
    final colorName = colorIdentityNames[widget.color] ?? widget.color;
    final positiveSuggestions =
        wheelTaskSuggestions.where((s) => s.positive).toList();
    final negativeSuggestions =
        wheelTaskSuggestions.where((s) => !s.positive).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ManaSymbol(color: widget.color, size: 28),
                const SizedBox(width: 8),
                Text(
                  'Aufgabe für $colorName · Stufe ${widget.stage}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 200,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Aufgabe',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vorschläge (antippen übernimmt den Text, danach frei '
              'editierbar):',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('Positiv', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in positiveSuggestions)
                  ActionChip(
                    label: Text(s.chipLabel),
                    tooltip: s.text,
                    onPressed: () => _applySuggestion(s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Negativ', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in negativeSuggestions)
                  ActionChip(
                    label: Text(s.chipLabel),
                    tooltip: s.text,
                    onPressed: () => _applySuggestion(s),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final text = _controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.of(context).pop(text);
                  },
                  child: const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
