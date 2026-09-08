# track_and_play

Track & Play - Partien, Spieler und Decks erfassen und auswerten.
Nachfolger-App zu mtg_stats, komplett neu aufgesetzt (kein Fork).

Details zu Entscheidungen, Datenmodell und nächsten Schritten:
siehe [ARCHITECTURE.md](./ARCHITECTURE.md).

## Erste Schritte

1. Einmalig die Plattform-Ordner erzeugen (Android/iOS/Windows/Linux/macOS/Web),
   ohne die bereits vorhandenen lib/pubspec-Dateien zu überschreiben:

   ```
   flutter create --org com.trackandplay --project-name track_and_play .
   ```

2. Abhängigkeiten holen und Datenbank-Code generieren:

   ```
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```

3. Starten:

   ```
   flutter run
   ```
