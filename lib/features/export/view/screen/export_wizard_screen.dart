import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../settings/controller/provider/app_settings_provider.dart';
import '../../controller/provider/export_service_provider.dart';
import '../../model/export_selection.dart';

/// Export-Wizard: Auswahl der Kategorien (Spieler/Decks/Gruppen/
/// Partien), dann entweder Teilen als JSON-Datei über das
/// System-Share-Sheet (siehe ExportService, share_plus) oder direktes
/// Speichern in einen selbst gewählten Ordner (file_picker,
/// FilePicker.platform.saveFile - nutzt auf Android/iOS den nativen
/// Speichern-unter-Dialog (Storage Access Framework), damit man - anders
/// als beim Share-Sheet, das nur Ziel-Apps anbietet - direkt ein
/// Zielverzeichnis auswählen kann). Für den schnellen QR-Austausch eines
/// einzelnen Decks/Spielers siehe stattdessen die "Teilen (QR)"-Aktionen
/// auf der jeweiligen Detailseite (PlayerDetailScreen,
/// qr_share_dialog.dart).
class ExportWizardScreen extends ConsumerStatefulWidget {
  const ExportWizardScreen({super.key});

  @override
  ConsumerState<ExportWizardScreen> createState() =>
      _ExportWizardScreenState();
}

class _ExportWizardScreenState extends ConsumerState<ExportWizardScreen> {
  ExportSelection _selection = const ExportSelection();
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final trackOtherPlayers = settingsAsync.maybeWhen(
      data: (s) => s.trackOtherPlayers,
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Daten exportieren')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Erstellt eine JSON-Datei mit den ausgewählten Daten, die du '
            'z. B. per Messenger oder E-Mail verschicken oder als Backup '
            'sichern kannst.',
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Spieler'),
            value: _selection.includePlayers,
            onChanged: (v) =>
                setState(() => _selection = _selection.copyWith(includePlayers: v)),
          ),
          CheckboxListTile(
            title: const Text('Decks'),
            value: _selection.includeDecks,
            onChanged: (v) =>
                setState(() => _selection = _selection.copyWith(includeDecks: v)),
          ),
          if (trackOtherPlayers)
            CheckboxListTile(
              title: const Text('Gruppen'),
              value: _selection.includeGroups,
              onChanged: (v) => setState(
                () => _selection = _selection.copyWith(includeGroups: v),
              ),
            ),
          CheckboxListTile(
            title: const Text('Partien'),
            value: _selection.includeGames,
            onChanged: (v) =>
                setState(() => _selection = _selection.copyWith(includeGames: v)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed:
                _isExporting ? null : () => _shareAsFile(trackOtherPlayers),
            icon: const Icon(Icons.ios_share),
            label: Text(_isExporting ? 'Exportiere…' : 'Als Datei teilen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                _isExporting ? null : () => _saveToFolder(trackOtherPlayers),
            icon: const Icon(Icons.folder_open),
            label: Text(_isExporting ? 'Exportiere…' : 'In Ordner speichern'),
          ),
        ],
      ),
    );
  }

  /// Baut den Export-Bundle-JSON-String anhand der aktuellen Auswahl.
  /// Gemeinsam genutzt von [_shareAsFile] und [_saveToFolder], damit
  /// beide Export-Wege exakt dieselben Daten liefern.
  Future<String> _buildExportJson(bool trackOtherPlayers) async {
    // Ohne Gruppen-Funktion (trackOtherPlayers == false) gibt es
    // ohnehin keine Gruppen, aber die Checkbox ist dann ausgeblendet -
    // daher hier zusätzlich zur Sicherheit erzwungen statt sich auf
    // den zuletzt sichtbaren Checkbox-Wert zu verlassen.
    final effectiveSelection = trackOtherPlayers
        ? _selection
        : _selection.copyWith(includeGroups: false);
    final bundle =
        await ref.read(exportServiceProvider).build(effectiveSelection);
    return const JsonEncoder.withIndent('  ').convert(bundle.toJson());
  }

  String _exportFileName() {
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return 'track_and_play_export_$timestamp.json';
  }

  Future<void> _shareAsFile(bool trackOtherPlayers) async {
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await _buildExportJson(trackOtherPlayers);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_exportFileName()}');
      await file.writeAsString(json);
      // Hinweis: share_plus v12 API (SharePlus.instance.share mit
      // ShareParams) - bitte beim ersten Testlauf gegenprüfen, falls
      // der Analyzer hier eine andere Signatur erwartet.
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Track & Play Export'),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Speichert den Export direkt in einen vom Nutzer gewählten Ordner,
  /// statt über das System-Share-Sheet eine Ziel-App auszuwählen. Nutzt
  /// dafür FilePicker.platform.saveFile: auf Android/iOS/Web wird die
  /// Datei anhand von [bytes] direkt vom Picker geschrieben, auf
  /// Desktop-Plattformen liefert saveFile nur den gewählten Pfad zurück
  /// und die Datei muss selbst geschrieben werden - daher der
  /// `exists()`-Fallback unten, der beide Fälle abdeckt.
  Future<void> _saveToFolder(bool trackOtherPlayers) async {
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await _buildExportJson(trackOtherPlayers);
      final bytes = Uint8List.fromList(utf8.encode(json));
      // Hinweis: file_picker ^10.3.7 API (saveFile mit bytes-Parameter,
      // liefert auf Android/iOS/Web den bereits geschriebenen Pfad
      // zurück) - wie beim share_plus-Aufruf oben bitte beim ersten
      // Testlauf gegenprüfen, falls der Analyzer hier eine andere
      // Signatur erwartet.
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export speichern',
        fileName: _exportFileName(),
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (outputPath == null) {
        // Nutzer hat den Dialog abgebrochen.
        return;
      }
      final file = File(outputPath);
      if (!await file.exists()) {
        await file.writeAsBytes(bytes);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Gespeichert: $outputPath')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
