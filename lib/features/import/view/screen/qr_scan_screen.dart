import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scannt einen von Track & Play erzeugten Freigabe-QR-Code (einzelnes
/// Deck oder Spielerprofil, siehe ExportService) und gibt dessen
/// rohen JSON-Inhalt über Navigator.pop zurück - der eigentliche
/// Import läuft danach über denselben Weg wie der Datei-Import (siehe
/// ImportWizardScreen._loadRaw).
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR-Code scannen')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              _handled = true;
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
