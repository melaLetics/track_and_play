import 'package:flutter/material.dart';

/// Zeigt einen Umbenennen-Dialog mit einem einzelnen Textfeld.
///
/// WICHTIG (siehe ARCHITECTURE.md, Abschnitt "Bekannte Fixes"): der
/// TextEditingController wird bewusst als State dieses eigenen
/// StatefulWidgets verwaltet (initState/dispose) und NICHT manuell nach
/// einem awaited showDialog()-Aufruf entsorgt. Letzteres führte zuvor zu
/// "A TextEditingController was used after being disposed", weil
/// Navigator.pop() zwar sofort zurückkehrt, das AlertDialog-Widget
/// (inkl. TextField) aber noch für die Dauer seiner Exit-Animation im
/// Baum bleibt - wurde der Controller in diesem Fenster disposed, warf
/// ein Rebuild des noch sichtbaren TextFields die Exception, was in
/// der Folge zu einer kaskadierenden "_dependents.isEmpty"-Assertion
/// führte. Mit dem Controller im StatefulWidget-State ruft Flutter
/// dispose() garantiert erst auf, nachdem das Widget vollständig aus
/// dem Baum entfernt wurde.
///
/// [onSave] wird NACH dem Schließen des Dialogs aufgerufen (der
/// aufrufende Screen bleibt währenddessen gemountet) und kann dort
/// z. B. per async/await + try-catch einen Fehler als SnackBar anzeigen
/// (siehe ARCHITECTURE.md, Abschnitt "Bekannte Fixes": .catchError wird
/// in diesem Projekt bewusst nicht mehr verwendet).
Future<void> showRenameDialog(
  BuildContext context, {
  required String title,
  required String currentName,
  required String label,
  required int maxLength,
  required ValueChanged<String> onSave,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RenameDialog(
      title: title,
      currentName: currentName,
      label: label,
      maxLength: maxLength,
      onSave: onSave,
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  final String title;
  final String currentName;
  final String label;
  final int maxLength;
  final ValueChanged<String> onSave;

  const _RenameDialog({
    required this.title,
    required this.currentName,
    required this.label,
    required this.maxLength,
    required this.onSave,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    // Dialog sofort schliessen, danach erst den Callback (und damit
    // typischerweise einen DB-Schreibvorgang) auslösen - der darunter-
    // liegende Screen beobachtet den geänderten Datensatz oft live per
    // StreamProvider; würde erst geschrieben und danach gepoppt,
    // kollidiert der dadurch ausgelöste Rebuild mit dem Abbau der
    // Dialog-Route.
    Navigator.of(context).pop();
    widget.onSave(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
