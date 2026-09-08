import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../model/export_bundle.dart';

/// Defensiv deutlich unter der theoretischen QR-Kapazität gewählte
/// Obergrenze - ein einzelnes Deck, ein einzelner Spieler oder eine
/// einzelne Partie (siehe ExportService.buildDeckQrBundle/
/// buildPlayerQrBundle/buildGameQrBundle) passen dort in der Praxis
/// locker hinein. Etwas großzügiger als für Deck/Spieler allein
/// nötig, da eine Partie mit mehreren Teilnehmern (inkl. Notizen)
/// spürbar mehr Platz braucht.
const int _maxQrPayloadBytes = 2500;

/// Zeigt ein Bundle (ein einzelnes Deck, ein einzelner Spieler ODER
/// eine einzelne Partie) als QR-Code in einem Dialog. Bei zu großer
/// Payload (in der Praxis kaum zu erreichen) erscheint stattdessen ein
/// Hinweis auf den Datei-Export.
Future<void> showQrShareDialog(
  BuildContext context, {
  required String title,
  required ExportBundle bundle,
}) {
  final json = jsonEncode(bundle.toJson());
  final tooLarge = utf8.encode(json).length > _maxQrPayloadBytes;

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: tooLarge
          ? const Text(
              'Diese Daten sind für einen einzelnen QR-Code zu umfangreich. '
              'Bitte stattdessen den Datei-Export verwenden.',
            )
          : SizedBox(
              width: 260,
              height: 260,
              child: QrImageView(data: json, size: 260),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}
