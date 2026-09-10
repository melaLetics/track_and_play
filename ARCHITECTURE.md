# Architektur & Entscheidungen - track_and_play

Dieses Dokument hält fest, wie track_and_play als eigenständiger
Nachfolger von mtg_stats aufgesetzt wurde: Entscheidungen, Datenmodell
und offene nächste Schritte. Es dient als Gedächtnis für zukünftige
Arbeitssitzungen an diesem Projekt.

## Grundsatzentscheidungen (mit dem Nutzer abgestimmt)

1. **Kein Fork von mtg_stats.** Neues Flutter-Projekt von Grund auf,
   nur Idee/Konzept und die Badge-Grafiken wurden übernommen.
2. **Datenaustausch:** Datei-Export/Import (JSON-Bundle, Versand per
   Share-Sheet/Messenger) **plus** QR-Code für schnellen Austausch
   kleiner Datenmengen (einzelnes Deck/einzelner Spieler/einzelne
   Partie) ohne Datei-Umweg.
3. **Unbekannte Spieler/Decks bleiben dauerhaft anonym.** Sie werden
   nie zu vollen Profilen "hochgestuft".
4. **Package-ID:** Platzhalter `com.trackandplay` (Android
   applicationId / iOS Bundle-ID), kann jederzeit vor Veröffentlichung
   geändert werden.
5. **Mehrere Spielgruppen werden unterstützt** (z. B. "Freitagsrunde",
   "Familienrunde"), **aber Gruppen sind komplett optional.** Reiner
   Solo-Betrieb (nur eigene Partien/Decks erfassen und auswerten, ohne
   je eine Gruppe anzulegen) muss uneingeschränkt weiter funktionieren -
   das war dem Nutzer ausdrücklich wichtig.
6. **Zwei Erfassungsarten für Partien:** "Manuelles Nachtragen" (z. B.
   am nächsten Tag, ohne Extras) oder "Live-Erfassung" während der
   Partie - Letztere bringt zusätzlich einen Lebenspunktezähler, eine
   automatische Dauer-Messung und die Ermittlung von "First Blood"
   (wer zuerst Lebenspunkte verliert) mit. Diese drei Extras sind
   bewusst an die Live-Erfassung gekoppelt, nicht am manuellen
   Nachtragen verfügbar (siehe Datenmodell unten).

## Datenmodell (Drift, lib/database/tables/)

- **Players**: `id, name, isSelf, archived, createdAt`.
  Genau ein Datensatz hat `isSelf = true` (der Nutzer selbst). Ein
  Player ist eine globale Identität, unabhängig von Gruppen.
- **Groups**: `id, name, archived, createdAt`. Eine eigene Spielgruppe.
  Rein optional - ohne angelegte Gruppe verhält sich die App wie ein
  reiner Solo-Tracker.
- **PlayerGroupMemberships**: `id, playerId (FK Players), groupId (FK
  Groups), joinedAt`. Many-to-many: ein Player kann Mitglied in keiner,
  einer oder mehreren Gruppen sein (man selbst spielt z. B. in mehreren
  Runden mit; ein Freund evtl. nur in einer). Unique auf
  (playerId, groupId).
- **Decks**: `id, ownerPlayerId (FK Players), name, colorIdentity,
  commanderName, secondCommanderName, buildType, bracket, isProxy,
  isTournamentLegal, deckLink, archived, createdAt`. Decks gehören immer
  einem bekannten Player, **nicht** einer Gruppe - welche Gruppe ein
  Deck gerade nutzt, ergibt sich aus den Partien, in denen es gespielt
  wird. `secondCommanderName` (Partner-/zweiter Commander),
  `buildType` (Enum precon/upgraded/homebrew), `bracket` (Power-Level,
  z. B. 1-5), `isProxy`, `isTournamentLegal` und `deckLink` wurden 1:1
  aus mtg_stats_tracker (`AppDeck`) übernommen, damit dort erfasste
  Deck-Informationen nicht verloren gehen.
- **Games**: `id, playedAt, mode (commander/competitiveCommander/
  twoHeadedGiant/archenemy), notes, groupId (FK Groups, nullable),
  createdAt`. `groupId` ist `null` für rein persönlich erfasste
  Partien ohne Gruppenbezug - genau das ermöglicht den vollwertigen
  Solo-Betrieb ohne jede Gruppe. `competitiveCommander` (cEDH) nutzt
  dieselbe Teilnehmer-/Datenstruktur wie `commander` (EDH) - es ist
  nur ein weiterer Modus-Wert, kein eigenes Datenmodell nötig.

  Für die Live-Erfassung zusätzlich:
  - `entryMode` (`manual`/`live`) - wie die Partie erfasst wurde.
  - `status` (`inProgress`/`completed`) - manuell nachgetragene Partien
    werden immer direkt als `completed` angelegt; live erfasste starten
    als `inProgress` und wechseln beim Beenden zu `completed`.
  - `startedAt` (nullable) - Startzeitpunkt der Live-Erfassung, damit
    die Dauer auch nach einem App-Neustart weiterberechnet werden kann.
  - `durationSeconds` (nullable) - Gesamtdauer; bei Live-Erfassung
    automatisch beim Beenden gesetzt, bei manuellem Nachtragen optional.
  - `firstBloodParticipantId` (nullable) - **logischer** Verweis auf
    `GameParticipants.id` (bewusst keine Drift-FK-Referenz, um einen
    Zyklus zwischen Games und GameParticipants zu vermeiden). Wird nur
    bei Live-Erfassung gesetzt.
  - `isDraw` (bool, default false) - Unentschieden. Bei `true` müssen
    alle Teilnehmer (bzw. beide Seiten bei Team-Formaten) denselben
    Platz belegen - siehe Validierungsregeln unten.

- **GameParticipants**: ein Sitzplatz in einer Partie. Entweder
  - bekannt: `playerId` + `deckId` gesetzt, oder
  - anonym: `anonymousLabel` (optional) + `anonymousColorIdentity`
    gesetzt, `playerId`/`deckId` bleiben `null`.

  Dazu:
  - `startPosition` (nullable int) - Zugreihenfolge, wird vor
    Spielbeginn auf dem Setup-Screen vergeben und muss über alle
    Teilnehmer einer Partie eindeutig sein (auch in Team-Formaten,
    da jeder einzeln am Zug ist).
  - `placement` (nullable int) - Endplatzierung. Bei Commander/cEDH
    individuell je Spieler (1..N, eindeutig, außer bei Unentschieden);
    bei Two-Headed Giant/Erzfeind teilen sich alle Mitglieder einer
    Seite denselben Platz (nur Platz 1/2 möglich).
  - `isWinner` (bool, denormalisiert) - wird beim Speichern aus
    `placement == 1` abgeleitet, kein eigenständig gesetztes Feld mehr.
  - `team` - bei Two-Headed Giant der Teamname (z. B. "A"/"B."), bei
    Erzfeind "archenemy" (genau ein Teilnehmer) oder "team" (Rest),
    bei Commander/cEDH ungenutzt (`null`).
  - `startingLife` (nullable, nur bei Live-Erfassung gesetzt, z. B. 40
    bei Commander).

- **LifeEvents** (neu, nur für live erfasste Partien): `id,
  gameParticipantId (FK GameParticipants), occurredAt, delta,
  resultingLife`. Ein Eintrag pro Lebenspunkte-Änderung während einer
  Live-Partie. Daraus lässt sich "First Blood" ableiten (zeitlich
  erster Eintrag mit `delta < 0` über alle Teilnehmer der Partie
  hinweg) sowie später ein Lebenspunkte-Verlaufsdiagramm für die
  Statistik.

- **AppSettings** (lib/features/settings/, shared_preferences statt
  Drift-Table, da einzelner globaler Zustand):
  - `trackOtherPlayers: bool` (vormals `trackGroup`) - schaltet
    grundsätzlich zwischen "nur ich" (Solo, keine Gruppen-/
    Mitspielerverwaltung sichtbar) und "auch andere Spieler/Gruppen
    verwalten" um.
  - `selfPlayerId: int?`.

**Getroffene Annahme** (noch nicht explizit abgefragt, aber aus dem
Datenmodell ableitbar): Ein Deck ist einem Player fest zugeordnet, aber
nicht an eine bestimmte Gruppe gebunden - dasselbe Deck kann also in
mehreren Gruppen gespielt werden, wenn der Owner in mehreren Gruppen
Mitglied ist. Falls Decks stattdessen strikt pro Gruppe getrennt
geführt werden sollen, müsste `Decks` zusätzlich ein optionales
`groupId` bekommen.

## Partien-Validierung (lib/features/games/model/game_setup_validator.dart)

Portiert/adaptiert aus mtg_stats_tracker (`game_create_validator.dart`),
um mit dem Nutzer abgestimmt: volle Platzierung je Teilnehmer (nicht
nur eine einfache Sieger-Markierung) und eine erfasste Startposition
(Zugreihenfolge) - siehe game_setup_validator.dart für die konkrete
Implementierung. Zwei Prüf-Einstiegspunkte:

- `validateGameSetup` - VOR dem Spiel (Teilnehmerzahl-Grenzen,
  eindeutige Spieler, eindeutige Startpositionen, Team-/Erzfeind-
  Zuordnung). Wird sowohl vor dem Start einer Live-Partie als auch als
  Teil der vollen Prüfung unten verwendet.
- `validateGameResult` - zusätzlich die Platzierung, vor dem manuellen
  Speichern bzw. vor dem Beenden einer Live-Partie.

Regeln je Modus (`gameModeRules`):
- **Commander/cEDH**: 2-6 Teilnehmer, keine Teams. Platzierung
  individuell: bei Unentschieden identischer Platz für alle, sonst
  eindeutig durchnummeriert 1..N.
- **Erzfeind**: 3-6 Teilnehmer, genau einer mit `team == 'archenemy'`,
  die übrigen 2-5 bilden das Team dagegen. Platzierung: alle
  Team-Mitglieder teilen sich einen Platz, der Erzfeind einen anderen
  (nur Platz 1/2), außer bei Unentschieden (alle gleich).
- **Two-Headed Giant**: mindestens 4 Teilnehmer, exakt zwei gleich
  große Teams (**Annahme, noch nicht explizit vom Nutzer bestätigt:**
  mindestens 2 Spieler pro Team - bewusst flexibler als
  mtg_stats_tracker, das dort starr auf 2v2/4 Spieler beschränkt war).
  Platzierung: beide Teams teilen sich je einen Platz (1/2), außer bei
  Unentschieden.

UI-seitig (siehe `GameSetupScreen`/`LiveGameScreen`):
- Startposition und Team-/Erzfeind-Zuordnung werden bereits auf dem
  Setup-Screen festgelegt (vor dem Spiel bekannt).
- Bei manueller Erfassung wird die Platzierung direkt mit erfasst
  (individuelle Platz-Stepper bei Commander/cEDH, Sieger-Team- bzw.
  Erzfeind-Auswahl bei Team-Formaten) plus "Unentschieden"-Checkbox.
- Bei Live-Erfassung wird dieselbe Platzierungs-Abfrage erst im
  "Partie beenden"-Dialog gestellt (Ergebnis ist ja vorher nicht
  bekannt) - nutzt dieselbe Validierungsfunktion.
- Ein Validierungsfehler wird als Banner/Dialog-Text angezeigt, der
  jeweilige Speichern-/Bestätigen-Button ist so lange deaktiviert.

## Badges (lib/features/achievements/)

Alle Badge-Grafiken wurden 1:1 aus `mtg_stats/assets/badges/` in
`assets/badges/` kopiert (Streaks, Partien-/Sieg-Meilensteine,
Farbchampion mono/zwei/drei/vier/fünffarbig, Wochentags-Serien,
Spezial-Badges wie "Erster Sieg", "Newbie" etc.).

`lib/features/achievements/model/badge_definitions.dart` enthält den
vollständigen Katalog als statische Liste (`allBadges`), generiert aus
den Asset-Pfaden.

**Freischalt-Logik fertig** (`lib/features/achievements/model/
achievement_engine.dart`, `computeAchievements` - reine Funktion ohne
DB-Zugriff, analog zu `player_stats.dart`): berechnet für ALLE Badges
im Katalog, ob und wann sie freigeschaltet wurden, aus den
abgeschlossenen Partien-Teilnahmen des Ich-Spielers
(`GamesRepository.watchSelfGameStats` - derselbe Datenstrom wie das
Statistik-Dashboard, hier aber bewusst UNGEFILTERT nach Gruppe/Modus).
Mit dem Nutzer abgestimmter Umfang (siehe "Bekannte Fixes" unten für
die Details): nur für den Ich-Spieler, Achievements zählen global über
alle Gruppen hinweg (nicht getrennt je Gruppe). Anzeige über
`AchievementsScreen` (neuer Button "Meine Erfolge" auf dem
Home-Screen): alle Badges des Katalogs gruppiert nach Kategorie, auch
gesperrte (ausgegraut), damit erkennbar ist, was noch zu erreichen
ist - bewusst nur eine funktionale Card/Wrap-Darstellung, die
optische Aufbereitung ist laut Nutzer auf ganz zuletzt verschoben
(siehe "Noch zu bauen" unten).

## Export/Import (lib/features/export/, lib/features/import/)

**Fertig.** Siehe "Bekannte Fixes" für die vollständige Beschreibung
(mit dem Nutzer abgestimmte Design-Fragen, Namens-basierte
Referenzierung statt lokaler IDs, Duplikat-Erkennung).

- `ExportSelection`: Auswahl, welche Kategorien (Players/Decks/
  Groups/Games) beim Datei-Export enthalten sein sollen.
- `ExportBundle`: das Austauschformat (JSON, `schemaVersion`) -
  referenziert Verknüpfungen (Deck->Besitzer, Gruppe->Mitglieder,
  Partie->Teilnehmer/Gruppe) bewusst per NAME statt per lokaler
  Drift-Autoincrement-id, da diese IDs geräteübergreifend nichts
  Sinnvolles referenzieren würden.
- `ExportService` (`lib/features/export/controller/`): baut das
  Bundle aus der Datenbank - `build(ExportSelection)` für den
  Datei-Export, `buildDeckQrBundle`/`buildPlayerQrBundle` für den
  QR-Export (siehe unten).
- Zwei Übertragungswege, beide nutzen dasselbe `ExportBundle`-Format:
  1. **Datei** (`ExportWizardScreen`): vollständiges/ausgewähltes
     Bundle als JSON-Datei, wahlweise Versand über `share_plus`
     (`SharePlus.instance.share`, System-Teilen-Sheet mit Ziel-App-
     Auswahl - Button "Als Datei teilen") oder direktes Speichern in
     einen selbst gewählten Ordner über `FilePicker.platform.saveFile`
     (nativer Speichern-unter-Dialog/Storage Access Framework - Button
     "In Ordner speichern", siehe "Bekannte Fixes" für den Hintergrund).
     Einlesen über `file_picker` (`pickFiles`).
  2. **QR-Code** (`qr_flutter`/`mobile_scanner`): "Teilen (QR)" auf
     `PlayerDetailScreen` (pro Deck, Zeilen-Icon, und für den Spieler
     selbst, App-Bar-Menü) sowie auf `GameDetailScreen` (eine
     abgeschlossene Partie, App-Bar-Icon) - jeweils ein Bundle mit
     genau einem Eintrag, siehe QR-Design-Entscheidung unten.
     `QrScanScreen` scannt und gibt den rohen JSON-Inhalt zurück, der
     danach genauso wie ein Datei-Import verarbeitet wird.
- **Teilnehmer-Zuordnung beim Import von Partien** (`GameImportTile`,
  `ParticipantOverride`): unabhängig vom automatischen Namens-Abgleich
  kann jeder Partie-Teilnehmer in der Vorschau (aufklappbar) manuell
  "on the fly" einem bereits bekannten lokalen Spieler zugeordnet
  werden (der Ich-Spieler oder ein anderer bekannter Spieler) samt
  Auswahl eines EIGENEN Decks - z. B. um einen per QR geteilten
  Teilnehmer, der nur mit Farbidentität "WU" erfasst ist, als sich
  selbst zu erkennen und dafür das eigene passende WU-Deck
  auszuwählen, statt sich auf Namensgleichheit zu verlassen. Dafür
  trägt `GameParticipantExport` jetzt zusätzlich ein `colorIdentity`-
  Feld (immer gesetzt, unabhängig davon ob das Deck selbst mit im
  Bundle ist) - siehe "Bekannte Fixes" für die Details. Ein weiteres
  Feld `deckOwnerName` referenziert (nur bei einem GELIEHENEN Deck
  gesetzt, siehe Deck-Verleih weiter unten) den tatsächlichen
  Deck-Besitzer statt des Teilnehmers selbst.
- `ImportService` (`lib/features/import/controller/`): `parseBundle`
  (JSON -> `ExportBundle`, mit nutzerfreundlichem Fehler bei
  unbekannter `schemaVersion`), `buildPreview` (Duplikat-Erkennung,
  siehe unten), `performImport` (eigentlicher Datenbank-Import, in
  einer Transaktion).
- `ImportWizardScreen`: Quelle wählen (Datei/QR) -> Vorschau mit
  Checkboxen je Eintrag (vorausgewählt/-abgewählt siehe
  Duplikat-Erkennung) -> Import -> Ergebnis inkl. Hinweise zu nicht
   1:1 übernommenen Einträgen.

## Aktueller Stand / nächste Schritte

Bereits vorhanden:
- Projektstruktur (`lib/core`, `lib/database`, `lib/features/*`)
- Drift-Schema inkl. Groups/PlayerGroupMemberships (Players, Decks,
  Groups, PlayerGroupMemberships, Games, GameParticipants)
- Badge-Katalog + Assets
- **App-Icon + Android-Splash-Screen fertig** (1:1 vom
  mtg_stats_tracker-Vorgänger übernommen, siehe "Bekannte Fixes")
- **App-Theme "Vault & Foil" fertig** (`lib/core/theme/app_theme.dart`,
  aktuell fest auf Dunkel gestellt, siehe "Bekannte Fixes")
- **Bottom Navigation fertig** (`lib/features/home/view/main_shell.dart`,
  `MainShell`, vier Tabs: Home/Decks/Statistik/Partien), siehe
  "Bekannte Fixes")
- **Export/Import fertig** (siehe eigener Abschnitt oben und "Bekannte Fixes")
- **Home-Dashboard fertig (erste Ausbaustufe)**
  (`lib/features/home/view/widgets/`): Begrüßung, Erinnerung an die
  letzte Partie (ab 1 Tag), Random-Deck-Funktion inkl. Bracket-/Art-/
  Proxy-Filter, Elo-Score-Barometer, Vorschau der letzten Erfolge mit
  Link zum vollen Erfolge-Screen, kompakte "Weitere Optionen"-Card
  (Export/Import/Gruppen verwalten) - 1:1 vom Umfang mit dem Nutzer
  abgestimmt, siehe "Bekannte Fixes" unten. Weitere mtg_stats-
  Dashboard-Karten (Winrate/Win-Streak/Usual-Suspects/Backup-Reminder)
  bewusst NICHT übernommen, da nicht angefordert.
- Riverpod-Provider für Datenbank, Players- und Groups-Repository
  (`lib/database/provider/`, `lib/features/players/controller/`,
  `lib/features/groups/controller/`)
- Settings-Controller (`SettingsController`, AsyncNotifier) zum Lesen/
  Schreiben der AppSettings
- **Setup-Wizard fertig** (`lib/features/setup/`): fragt Solo vs.
  Gruppen ab, legt den `isSelf`-Player an, erlaubt optional das direkte
  Anlegen der ersten Gruppe. `AppRoot` in `main.dart` zeigt automatisch
  den Wizard, solange noch kein Self-Player existiert, danach die
  `MainShell` mit Bottom Navigation (siehe eigene Zeile unten und
  "Bekannte Fixes").
- **Gruppen-Verwaltung fertig** (`lib/features/groups/view/`):
  Übersicht (Liste + Mitgliederzahl, neue Gruppe anlegen - fügt
  automatisch den Self-Player als Mitglied hinzu), Detailscreen
  (umbenennen, archivieren, Mitglieder anzeigen/entfernen, neues
  oder bestehendes bekanntes Mitglied hinzufügen inkl. Schnell-
  Anlage eines neuen Spielers). Einstieg über den Home-Screen, aber
  nur sichtbar, wenn `AppSettings.trackOtherPlayers == true`.
- **Spieler-/Deck-Verwaltung fertig, inkl. mtg_stats_tracker-Deck-
  Feldern** (`lib/features/players/view/`, `lib/features/decks/`):
  `PlayerDetailScreen` zeigt einen Spieler (sich selbst oder ein
  Gruppenmitglied) mit seinen Decks, erlaubt Umbenennen und - außer
  beim Self-Player - Archivieren. Decks werden über `DeckFormDialog`
  angelegt/bearbeitet/archiviert, inkl. `ColorIdentityPicker`
  (WUBRG-Toggle-Chips), optionalem Commander- UND Partner-Commander-
  Namen, Bauart (precon/upgraded/homebrew), Bracket (1-5), Proxy-/
  Turnierlegal-Checkboxen und optionalem Online-Link - alles 1:1 aus
  mtg_stats_tracker übernommen (siehe Datenmodell-Abschnitt oben).
  Erreichbar über "Meine Decks" auf dem Home-Screen (immer sichtbar,
  unabhängig vom Solo-/Gruppen-Schalter) sowie durch Antippen eines
  Mitglieds in der Gruppen-Detailansicht.

- **Partien erfassen fertig, inkl. Modus-Validierung**
  (`lib/features/games/`): Umschalter "Manuell nachtragen"/"Live
  erfassen" oben auf `GameSetupScreen`, Modus-Auswahl
  (Commander/cEDH/2HG/Archenemy), optionale Gruppenzuordnung,
  Teilnehmer bekannt (`AddKnownParticipantDialog`: Spieler + optional
  eines seiner Decks) oder anonym (`AddAnonymousParticipantDialog`:
  optionales Label + Farbidentität). Der Self-Player wird beim Öffnen
  automatisch als erster Teilnehmer vorgeschlagen (kann entfernt
  werden). Pro Teilnehmer: Startposition (Stepper) sowie - je nach
  Modus - Team-/Erzfeind-Zuordnung (Chips). Siehe eigener Abschnitt
  "Partien-Validierung" oben für die genauen Modus-Regeln
  (Teilnehmerzahl, Team-Struktur, Platzierung) und
  `game_setup_validator.dart` - ein Validierungsfehler wird als Banner
  angezeigt und blockiert den jeweiligen Aktions-Button. Von dort aus
  zwei Wege:
  - **Manuell speichern**: legt die Partie sofort als `completed` an
    (`GamesRepository.createManualGame`), inkl. Datum, Notizen,
    Platzierung je Teilnehmer (bzw. Sieger-Team/-Erzfeind-Auswahl) und
    optionalem Unentschieden.
  - **Live-Erfassung starten** (`LiveGameScreen`): Lebenspunktezähler
    pro Teilnehmer (Start-Lebenspunkte frei einstellbar auf dem
    Setup-Screen), Dauer-Timer ab Start, automatische "First Blood"-
    Markierung beim ersten negativen Lebenspunkte-Delta
    (`GamesRepository.recordLifeChange`) sowie beim Beenden derselbe
    Platzierungs-Dialog wie bei der manuellen Erfassung
    (`GamesRepository.finishLiveGame`, berechnet `durationSeconds`).
    Nicht pausierbar (wie vom Nutzer bestätigt). Bei Commander/cEDH
    wird im Platzierungs-Dialog zusätzlich ein **Platzierungs-
    Vorschlag** vorbelegt (siehe eigener Fixes-Eintrag unten "Platzierungs-
    Vorschlag am Ende der Live-Erfassung").
  `GamesOverviewScreen` (Historie, neueste zuerst) und
  `GameDetailScreen` (Modus, Datum, Gruppe, Dauer, Unentschieden-
  Hinweis, Notizen, Teilnehmer sortiert nach Platzierung inkl. Start-
  position/Team/First-Blood-Markierung, Namen über
  `GamesRepository.watchParticipantViews`-Join aufgelöst) runden das
  Feature ab. Einstieg über zwei neue Buttons auf dem Home-Screen
  ("Neue Partie erfassen" / "Partien-Historie").

  **Bekannte Einschränkung:** Wird eine Live-Partie verlassen, ohne sie
  über "Partie beenden" abzuschließen, bleibt sie dauerhaft im Status
  `inProgress` (kein Fortsetzen-Dialog in der Detailansicht bisher) -
  das war für den ersten Test-Durchlauf nicht relevant, sollte aber vor
  einer echten Nutzung nachgerüstet werden (z. B. Live-Screen aus
  gespeichertem `startedAt` + letztem `LifeEvent` je Teilnehmer wieder
  aufbauen).

  **Offene Detailfrage (noch nicht explizit bestätigt):**
  "First Blood" = zeitlich erster `LifeEvent` mit `delta < 0` über alle
  Teilnehmer der Partie hinweg, unabhängig von der Ursache (Gegner-
  Schaden, selbst bezahlte Kosten, Board-Wipe etc.). Falls nur
  gegnerisch verursachter Schaden zählen soll, bräuchte `LifeEvents`
  zusätzlich ein Feld wie `causedByParticipantId` - bislang nicht
  vorgesehen.

- **Statistik-Dashboard fertig (erste Ausbaustufe)**
  (`lib/features/stats/`): `StatsScreen` zeigt die eigene Siegquote
  (gesamt und aufgeschlüsselt nach Deck), berechnet aus allen
  ABGESCHLOSSENEN Partien-Teilnahmen des Ich-Spielers
  (`GamesRepository.watchSelfGameStats`, `computePlayerStats` in
  `lib/features/stats/model/player_stats.dart` - reine Funktion ohne
  DB-Zugriff, analog zu `game_setup_validator.dart`). Mit dem Nutzer
  abgestimmter Umfang dieser ersten Version (siehe "Bekannte Fixes"
  unten): global mit Umschalter auf eine bestimmte Gruppe (Dropdown nur
  sichtbar, wenn `trackOtherPlayers == true`) UND auf einen bestimmten
  Modus (EDH/cEDH/2HG/Erzfeind, immer sichtbar, beide Filter
  unabhängig voneinander kombinierbar), nur Siegquote (nicht
  Streaks/First-Blood-Quote/Ø-Dauer), nur die eigene Statistik (kein
  Vergleich zwischen mehreren Spielern einer Gruppe). Einstieg über
  einen neuen Button "Meine Statistik" auf dem Home-Screen.

  **Erweiterung: Performance-Korrelationen + Elo-Score**
  (`lib/features/stats/model/player_performance_stats.dart`), auf
  Nutzeranfrage ergänzt (siehe "Bekannte Fixes" unten für die mit dem
  Nutzer abgestimmten Design-Entscheidungen): zusätzliche
  Siegquoten-Aufschlüsselung nach Farbidentität (über Decks hinweg,
  nicht nur pro Deck), nach Startposition (Terzile Früh/Mittel/Spät,
  normiert auf die jeweilige Teilnehmerzahl) und nach Partiendauer
  (Terzile Kurz/Mittel/Lang, nur Live-erfasste Partien), sowie ein
  Elo-artiger Performance-Score (0-100, `computeEloScore`) nur für den
  Ich-Spieler. Alle vier respektieren dieselben Gruppen-/Modus-Filter
  wie der Rest des Dashboards. `SelfGameStatsRow` führt dafür
  zusätzlich `placement`, `startPosition`, `participantCount`,
  `durationSeconds` und `isDraw` mit; `GamesRepository.
  watchSelfGameStats` gruppiert dafür jetzt ALLE Teilnehmer jeder
  Partie (nicht nur den Ich-Spieler) in Dart nach `gameId`, um
  `participantCount` zu ermitteln.

Noch zu bauen (in dieser Reihenfolge sinnvoll):
1. Statistik-Dashboard, weitere Kennzahlen (mit dem Nutzer bewusst auf
   eine spätere Version verschoben, siehe oben): Streaks (aktuelle/
   längste Sieg-Serie), First-Blood-Quote, Partienanzahl & Ø-Dauer,
   sowie optional ein Gruppen-Vergleich zwischen mehreren Spielern.
   (Die Modus-Differenzierung selbst - EDH/cEDH/2HG/Erzfeind - ist seit
   dem Modus-Filter-Nachtrag bereits vorhanden, ebenso die
   Siegquoten-Korrelationen nach Farbidentität/Startposition/
   Partiendauer und der Elo-Score, siehe "Bekannte Fixes".)
2. **Optische Aufbereitung der Statistik- UND Erfolge-Anzeige**
   (`StatsScreen` und `AchievementsScreen` mit ihren jeweiligen Karten/
   Listen) - vom Nutzer ausdrücklich auf GANZ ZULETZT verschoben, also
   erst NACHDEM alle anderen offenen Punkte in dieser Liste (inkl. der
   weiteren Statistik-Kennzahlen oben) umgesetzt sind. Bislang rein
   funktionale, ungestylte Darstellung (Standard-`Card`/`ListTile`/
   `Wrap`, keine Diagramme/Sparklines, kein besonderes Layout für den
   Elo-Score oder die Badge-Galerie). Nicht von selbst anfangen, auch
   wenn sonst nichts mehr auf der Liste steht - erst wenn der Nutzer
   das explizit anstößt.

## Bekannte Fixes

- **Bugfix: eigene Decks beim Import fälschlich blockiert, wenn
  der eigene Name als Duplikat erkannt wird** (Nutzer-Bugreport:
  "wenn mein eigener Name als 'vermutlich bereits vorhanden'
  markiert und daher nicht importiert wird, werden auch die Decks
  nicht importiert"). Ursache: die kürzlich eingeführte Deck<->
  Spieler-Kopplung (`_reconcileSelection`/`_deckSection`, siehe
  Eintrag weiter unten) prüfte NUR, ob der Deck-Besitzer unter
  `selection.selectedPlayerIndexes` (frisch zum Import ausgewählte
  Spieler) war - der eigene Self-Player ist aber praktisch immer
  ein per Namens-Abgleich erkanntes Duplikat und dadurch
  standardmäßig ABGEWÄHLT (er existiert ja lokal schon, ein
  erneuter Import würde nur einen zweiten Spieler mit demselben
  Namen anlegen). `ImportService.performImport` selbst hätte das
  Deck trotzdem korrekt importiert (`playerIdByName` wird dort
  zuerst mit dem GESAMTEN vorhandenen Datenbestand vorbelegt, ein
  Duplikat muss also gar nicht erneut ausgewählt sein, um als
  Besitzer aufgelöst zu werden) - nur die UI-Vorschau war
  strenger als die tatsächliche Import-Logik.
  Fix: neue Hilfsmethode `_resolvableOwnerNames` (genutzt von
  `_reconcileSelection` UND `_deckSection`) zählt einen
  Deck-Besitzer als auflösbar, wenn er ENTWEDER gerade zum Import
  ausgewählt ist ODER laut `ImportPreviewEntry.likelyDuplicate`
  bereits lokal existiert - unabhängig von seinem
  Auswahl-Status. Damit bleiben eigene Decks (Besitzer = eigener,
  als Duplikat erkannter Self-Player) jetzt korrekt vorausgewählt
  und anhakbar.

- **Gruppen-Import auf eigene Mitgliedschaft eingeschränkt**
  (Nutzer-Präzisierung zur vorherigen Gruppen/Spieler-Kopplung:
  "nur die Gruppen importieren, in denen man selber Mitglied
  ist"). Ersetzt die zuvor eingeführte, an die Spieler-AUSWAHL
  gekoppelte Gruppen-Vorauswahl (siehe vorheriger Eintrag oben) -
  diese griff nicht richtig, weil der eigene Self-Player meist gar
  nicht Teil von `selectedPlayerIndexes` ist (er existiert lokal
  bereits und wird beim Namens-Abgleich als Duplikat markiert und
  standardmäßig abgewählt) - eine Gruppe, in der nur man selbst
  Mitglied ist, wäre dadurch nie automatisch importiert worden.
  Jetzt stattdessen ein harter Filter direkt in
  `ImportService.buildPreview` - analog zum bereits vorhandenen
  Partien-Filter (selbe Namens-Abgleich-Variable `selfNameLower`,
  jetzt vor beiden Schleifen berechnet statt nur vor der
  Partien-Schleife): eine Gruppe erscheint nur dann überhaupt in
  der Vorschau (wählbar/importierbar), wenn `selfPlayerName` unter
  ihren `memberNames` vorkommt (case-insensitive) - unabhängig
  davon, welche anderen Spieler gerade zum Import ausgewählt sind.
  Wird kein `selfPlayerName` übergeben, entfällt der Filter (wie
  beim Partien-Filter). `ImportWizardScreen._reconcileSelection`
  kümmert sich jetzt nur noch um Decks (Besitzer muss unter den
  ausgewählten Spielern sein); die Gruppen-Sektion zeigt wie die
  Partien-Sektion einen Hinweistext, wenn Gruppen wegen fehlender
  eigener Mitgliedschaft herausgefiltert wurden. Der zuvor an
  `_section` ergänzte optionale `hint`-Parameter wurde wieder
  entfernt (ungenutzt, da nur für die jetzt überholte
  Gruppen-Erklärung gedacht).

- **Import-Vorschau: Gruppen-Auswahl, Spieler->Decks/Gruppen-
  Abhängigkeit sichtbar gemacht, Partien auf eigene Teilnahme
  gefiltert** (vier Beobachtungen aus einem Testlauf des Nutzers:
  Gruppen ließen sich "nicht" auswählen; Abwählen eines Spielers
  wirkte sich unsichtbar auf dessen Decks/Partien aus; bei
  Teilauswahl der Spieler sollten auch nur deren Gruppen importiert
  werden; Partien ohne eigene Teilnahme sollen gar nicht erst
  importiert werden).
  - **Partien-Filter (neu):** `ImportService.buildPreview` bekommt
    jetzt optional `selfPlayerName` - Partien, in denen dieser Name
    (Namens-Abgleich wie überall sonst im Import, case-insensitive)
    NICHT als Teilnehmer vorkommt, werden komplett aus der Vorschau
    gefiltert (kein `ImportPreviewEntry`, nicht wählbar, nicht
    importierbar) - Partien fremder Leute sind für den
    personenbezogenen Tracker irrelevant. `ImportWizardScreen._loadRaw`
    löst dafür vor `buildPreview` den lokalen Self-Player per
    `selfPlayerProvider` auf. Wird kein Name übergeben (Provider noch
    nicht geladen), entfällt der Filter statt fälschlich alles
    auszublenden. Wurden Partien gefiltert, zeigt die Vorschau einen
    Hinweistext mit der Anzahl.
  - **Deck<->Spieler-Kopplung (neu):** `ImportWizardScreen._deckSection`
    ersetzt für Decks die generische `_section` - ein Deck, dessen
    Besitzer aktuell nicht unter den ausgewählten Spielern ist, zeigt
    eine DEAKTIVIERTE Checkbox mit Untertitel "Besitzer nicht
    ausgewählt - wird nicht importiert" (es würde beim Import ohnehin
    per Warnung übersprungen, siehe `ImportService.performImport` -
    das ist jetzt schon in der Vorschau sichtbar statt erst danach als
    Warnliste).
  - **Gruppen<->Spieler-Kopplung (neu):** neue Methode
    `_reconcileSelection` (aufgerufen initial nach `buildPreview` UND
    bei jeder Änderung der Spieler-Auswahl) berechnet die
    Gruppen-Auswahl neu: nur Gruppen mit mindestens einem Mitglied
    unter den aktuell ausgewählten Spielern bleiben ausgewählt - im
    Unterschied zu Decks aber weiterhin bewusst FREI manuell änderbar
    (generische `_section`, jetzt mit optionalem `hint`-Text), da eine
    unvollständige Mitgliederliste beim Import kein Fehler ist
    (fehlende Mitglieder werden dort schon immer einfach übersprungen).
    `_reconcileSelection` entfernt auf demselben Weg auch Decks, deren
    Besitzer durch die Spieler-Änderung ungültig wurde (siehe oben).
  - **Gruppen-Auswahl selbst war KEIN Code-Defekt:**
    `ImportPreview.groups`/`ImportSelection.selectedGroupIndexes` und
    die `_section`-Checkbox-Logik dafür existierten strukturell schon
    identisch zu Spielern/Decks und funktionieren. Plausibelste
    Erklärung für die Beobachtung "kann Gruppen nicht auswählen":
    ohne die neue automatische Vorauswahl oben war die Gruppen-Liste
    beim Import entweder leer (kein `includeGroups` beim Export bzw.
    `trackOtherPlayers` aus) oder enthielt für die Teilauswahl
    irrelevante Gruppen, was sich wie "nicht nutzbar" angefühlt haben
    dürfte - mit der neuen Kopplung an die Spieler-Auswahl sollte sich
    das jetzt intuitiv richtig anfühlen. Bitte beim nächsten Testlauf
    gegenprüfen und melden, falls Gruppen weiterhin nicht wie erwartet
    erscheinen.

- **App-Anzeigename zu "TAP" geändert** (Nutzerwunsch: die App
  erschien auf dem Homescreen/Desktop noch mit dem technischen
  Projektnamen "track_and_play" statt einem sprechenden Namen).
  Geändert wurden ausschließlich die für den Nutzer sichtbaren
  Anzeige-Strings je Plattform - interne IDs bleiben unverändert,
  um Build-Konfiguration/Signierung/Store-Einträge nicht zu
  gefährden: `android:label` in `AndroidManifest.xml`;
  `CFBundleDisplayName`/`CFBundleName` in `ios/Runner/Info.plist`;
  `name`/`short_name` in `web/manifest.json` sowie `<title>` in
  `web/index.html`; `PRODUCT_NAME` in
  `macos/Runner/Configs/AppInfo.xcconfig`; `FileDescription`/
  `ProductName` in `windows/runner/Runner.rc` sowie der Fenstertitel
  in `windows/runner/main.cpp`; Fenstertitel (GTK-Headerbar und
  Fallback) in `linux/runner/my_application.cc`. Unverändert
  geblieben (bewusst, da interne Identifier statt Anzeigename):
  Android `applicationId`, iOS/macOS `PRODUCT_BUNDLE_IDENTIFIER`,
  Linux `APPLICATION_ID`, alle `BINARY_NAME`/Executable-Namen
  (Windows `.exe`, Linux-Binary), `pubspec.yaml`-Paketname sowie
  Windows `InternalName`/`OriginalFilename` (referenzieren weiter
  den unveränderten Datei-/Modulnamen `track_and_play`).

- **Export "In Ordner speichern" schlug auf Android im Downloads-
  Ordner fehl** (Nutzer-Bugreport auf physischem Android-Handy: "Das
  schlug fehl, da es den Ordner nicht gäbe"). Ursache in
  `ExportWizardScreen._saveToFolder`: `FilePicker.platform.saveFile(...)`
  schreibt die Bytes auf Android/iOS bereits selbst (Storage Access
  Framework); der zurückgelieferte `outputPath` ist dort - anders als
  auf Desktop - danach kein per `dart:io` nutzbarer echter
  Dateisystempfad mehr (insbesondere bei SAF-Sonderzielen wie
  "Downloads"). Der Code hat trotzdem unbedingt zusätzlich
  `File(outputPath).exists()` geprüft und bei `false` per
  `writeAsBytes` nachzuschreiben versucht - dieser fälschlich
  ausgelöste Zweitschreibversuch auf einen ungültigen Pfad war die
  Fehlerquelle, obwohl der Export vom Picker selbst bereits
  erfolgreich gespeichert worden war. Fix: der `exists()`/
  `writeAsBytes()`-Fallback läuft jetzt nur noch, wenn
  `Platform.isWindows || Platform.isLinux || Platform.isMacOS`
  (und `!kIsWeb`) - also ausschließlich dort, wo `saveFile` laut
  eigener Doku nur den Pfad liefert, ohne selbst zu schreiben. Auf
  Android/iOS/Web wird dem Picker-Schreibvorgang jetzt vertraut.

- **Suche/Filter in der Partien-Übersicht** (Nutzerwunsch: "nach
  Spieler, Commander oder Deck suchen" sowie "nach Modus filtern").
  Neu in `GamesRepository`: `GameListItem` (Partie + rohe,
  durchsuchbare Begriffe) und `watchGamesWithSearchTerms()` - LEFT
  JOIN ab Games (nicht ab GameParticipants, damit eine Partie ganz
  ohne Teilnehmer nicht aus der Liste faellt), sammelt je Partie
  Spielernamen (bekannt via Players.name UND anonym via
  GameParticipants.anonymousLabel), Decknamen sowie Commander-/
  Zweit-Commander-Namen aller Teilnehmer ein. Neuer Provider
  `gamesWithSearchTermsProvider` (games_repository_provider.dart).
  `GamesOverviewScreen` von `ConsumerWidget` auf
  `ConsumerStatefulWidget` umgestellt (analog zur Deck-Suche in
  `PlayerDetailScreen`): Such-Symbol blendet Suchfeld + Modus-
  Dropdown ein, die Filterung (Text-Teilstring-Suche ueber
  `searchTerms`, UND-verknuepft mit optionalem Modus-Filter) laeuft
  rein lokal, bevor die bereits vorhandene Jahr/Monat-Gruppierung
  greift. `recentGamesProvider`/`watchRecentGames` bleiben unveraendert
  bestehen (aktuell ohne eigenen Aufrufer mehr, aber als einfache
  "alle Partien ohne Suchbegriffe"-Abfrage fuer eine moegliche
  kuenftige Stelle nicht entfernt).

- **Hero-Fehler "multiple heroes ... default FloatingActionButton
  tag"** (Nutzer-Bugreport: Absturz-Log beim Öffnen einer
  historischen Two-Headed-Giant-Partie). Ursache: ALLE
  `FloatingActionButton`s in der App verzichten auf ein explizites
  `heroTag`, wodurch Flutter jedem intern denselben
  `_defaultHeroTag` gibt. `MainShell` haelt via `IndexedStack` alle
  vier Tabs dauerhaft gemountet (bewusst so, siehe deren Klassendoku -
  fuer den erhaltenen Scroll-Zustand), darunter der Decks-Tab
  (`PlayerDetailScreen`, FAB "Neues Deck") UND der Partien-Tab
  (`GamesOverviewScreen`, FAB "Neue Partie") - beide also gleichzeitig
  im Baum, beide mit demselben Default-Tag. Sobald irgendeine
  Navigation eine Hero-Flugsuche ausloest (z. B. `Navigator.push` auf
  `GameDetailScreen` beim Antippen einer Partie), findet Flutter ZWEI
  Heroes mit identischem Tag im selben Subtree und wirft die
  Assertion - unabhaengig vom Partien-Modus, das 2HG-Beispiel des
  Nutzers war vermutlich Zufall/erste Reproduktion, nicht die
  eigentliche Ursache. Fix: alle fuenf `FloatingActionButton`s der
  App (`games_overview_screen.dart`, `live_game_screen.dart`,
  `groups_overview_screen.dart`, `group_detail_screen.dart`,
  `player_detail_screen.dart`) haben jetzt ein festes, je Screen
  eindeutiges `heroTag` (String-Literal, z. B.
  'games_overview_fab') - damit koennen beliebig viele FABs
  gleichzeitig gemountet sein, ohne zu kollidieren.

- **Partien-Übersicht nach Jahr/Monat gruppiert** (Nutzerwunsch,
  angelehnt an mtg_stats_tracker - dort GameYearSection). Neu:
  `lib/core/utils/month_names.dart` (`monthNameDe`, 1:1 aus
  `core/globals.dart`/`monthName` des Vorgaengers uebernommen, aber
  bewusst als fest hinterlegte Liste statt ueber intl/DateFormat mit
  Locale-Initialisierung - `intl` wird in dieser App bislang nirgends
  fuer Datumsformatierung genutzt). `games_overview_screen.dart` hat
  eine neue private `_GameYearSection` (Card + ExpansionTile pro
  Jahr, `initiallyExpanded: true`, mit Partien-Anzahl im Titel), die
  darin je enthaltenen Monat wiederum als ExpansionTile zeigt (ohne
  `initiallyExpanded`, also zunaechst eingeklappt - wie im Vorbild)
  mit der bestehenden `_GameListTile` pro Partie darunter. Die
  Gruppierung selbst (`Map<int, Map<int, List<Game>>>` nach Jahr dann
  Monat, beide Ebenen absteigend sortiert) passiert direkt im
  `data:`-Builder von `GamesOverviewScreen`, die Partien-Reihenfolge
  innerhalb eines Monats bleibt die von `watchRecentGames` gelieferte
  (neueste zuerst). Ersetzt die bisherige flache
  `ListView.builder`-Liste.

- **Partien-Übersicht zeigte nur die letzten 50** (Nutzer-Feedback:
  im Partien-Tab fehlten aeltere Partien, obwohl der Klassenkommentar
  von `GamesOverviewScreen` "Historie ALLER erfassten Partien"
  verspricht). Ursache: `GamesRepository.watchRecentGames` hatte
  `int limit = 50` als Default, und `recentGamesProvider`
  (games_repository_provider.dart) rief die Methode ohne Override
  auf - der einzige Aufrufer dieser Methode ueberhaupt, also keine
  andere Stelle, die bewusst nur eine Teilmenge wollte. Signatur auf
  `{int? limit}` geaendert (Default: kein Limit, `.limit(limit)` nur
  noch aufgerufen wenn gesetzt) - Partien-Tab zeigt jetzt wirklich
  alle Partien, `limit` bleibt fuer eine moegliche kuenftige Stelle
  (z. B. ein "Letzte Partien"-Widget) optional nutzbar.

- **Gilden-/Keil-Namen bei "Nach Farbidentität"** (Nutzerwunsch: statt
  z. B. "UBR" soll "Grixis" stehen - angelehnt an mtg_stats_tracker,
  dort `MtgColorIdentity`-Enum in color_identity.dart). Neu:
  `lib/core/utils/color_identity_names.dart`
  (`colorIdentityNames`/`colorIdentityDisplayName`) - Mapping von
  normierter WUBRG-Farbidentitaet (siehe `normalizeColorIdentity`,
  color_identity_utils.dart) auf die jeweilige Bezeichnung: 10
  Gilden (2-farbig), 5 Shards + 5 Keile/Wedges (3-farbig), 5
  4-farbige Kombinationen (benannt nach der fehlenden Farbe) und
  WUBRG als "Fünffarbig" - Gilden-/Keil-Namen bleiben wie im
  Deutschen ueblich unuebersetzte Eigennamen (Grixis bleibt Grixis),
  nur Einfarbig/Fuenffarbig sind auf Deutsch (Einfarbig nutzt
  dieselben Bezeichnungen wie `ColorIdentityPicker._labels`). Wichtig:
  die Zuordnung ist NICHT 1:1 aus mtg_stats_tracker uebernommen,
  da dessen `shortName`-Feld pro Gilde uneinheitlich sortiert war
  (z. B. Selesnya dort "GW", Boros "RW") - hier stattdessen anhand
  der tatsaechlichen Farben je Gilde/Keil neu in die hier
  verbindliche WUBRG-Reihenfolge gebracht (z. B. Selesnya = "WG",
  Boros = "WR"), damit die Map-Keys exakt zu
  `normalizeColorIdentity`s Ausgabe passen. Eingesetzt nur in
  `stats_screen.dart`s `_bucketSection` (Aufruf fuer "Nach
  Farbidentität"): der Text neben den Mana-Symbolen zeigt jetzt
  `colorIdentityDisplayName(bucket.label)` statt des rohen Labels.

- **"Nach Deck" nach Eigene Decks/Decks anderer aufgeteilt**
  (Nutzerwunsch: seit dem Deck-Verleih kann ein Spieler auch ein
  FREMDES Deck spielen, siehe "Deck-Verleih" weiter unten in dieser
  Liste - das sollte in der "Nach Deck"-Statistik erkennbar sein
  statt alles in einen Topf zu werfen). Neues Feld
  `SelfGameStatsRow.isOwnDeck` (`games_repository.dart`,
  `watchSelfGameStats`/`_toSelfStatsRow`) - true bei
  `deck.ownerPlayerId == selfPlayerId` ODER ganz ohne Deck-Angabe
  (`deckId == null`), sonst false; durchgereicht auf
  `DeckWinStats.isOwnDeck` (`player_stats.dart`,
  `computePlayerStats` - Ownership ist pro deckId konstant, daher
  reicht der Wert der ersten Zeile je Bucket). In `stats_screen.dart`
  wird `stats.byDeck` jetzt nach `isOwnDeck` in zwei Listen
  aufgeteilt: eigene Decks wie bisher direkt unter "Nach Deck",
  fremde Decks darunter unter einer eigenen, dezenten Zwischen-
  ueberschrift "Decks anderer" (mit `Icons.swap_horiz`) und - auf
  Nutzerwunsch "etwas abgesetzt" - zusaetzlich eingerueckt
  (`Padding(left: 16)`) und leicht abgedunkelt (`Opacity(0.85)`).
  Die Card selbst wurde dafuer in einen gemeinsamen
  `_buildDeckCard`-Helper extrahiert, den beide Listen nutzen.

- **Groessere Mana-Symbole bei "Nach Deck"** (Nutzerwunsch, direkte
  Folge des vorherigen Punkts: nach Wegfall des begleitenden Texts
  durften die Symbole dort etwas groesser sein).
  `ManaSymbolRow(colorIdentity: deck.colorIdentity)` bekommt jetzt
  `size: 24` statt des Standardwerts 16 - nur an dieser Stelle, die
  "Nach Farbidentitaet"-Sektion bleibt bei der Standardgroesse, da
  dort Symbol UND Text nebeneinanderstehen.

- **Farbidentitaets-String bei "Nach Deck" entfernt** (Nutzerwunsch,
  direkte Folge des vorherigen Punkts: nachdem dort zusaetzlich die
  Mana-Symbole eingefuehrt wurden, war der rohe WUBRG-String
  redundant). Subtitle in der "Nach Deck"-Uebersicht zeigt jetzt nur
  noch `ManaSymbolRow(colorIdentity: deck.colorIdentity)` ohne
  begleitenden Text - bei farblosen Decks bleibt das eindeutige
  Colorless-Symbol sichtbar. Die "Nach Farbidentitaet"-Sektion
  (`_bucketSection` mit `showManaSymbols`) behaelt Symbol UND Text
  bewusst, da dort der Text (bzw. der Sammel-Text 'Kein Deck
  angegeben') die einzige Beschriftung der jeweiligen Card ist.

- **Mana-Symbole im Statistik-Screen** (Nutzerwunsch: ueberall dort,
  wo `stats_screen.dart` eine Farbidentitaet bislang nur als roher
  WUBRG-String zeigte, zusaetzlich die echten Mana-Symbole - analog
  zur Farbidentitaets-Auswahl beim Deck-Anlegen). Neu:
  `ManaSymbolRow` (`core/widgets/mana_symbol.dart`) - reiht
  `ManaSymbol` je Buchstabe einer Farbidentitaet aneinander, leerer
  String zeigt ein einzelnes farbloses Symbol. Eingesetzt an zwei
  Stellen: (1) "Nach Deck" - Subtitle zeigt jetzt
  `ManaSymbolRow(colorIdentity: deck.colorIdentity)` VOR dem
  bisherigen Text (Text bleibt, war explizit als "zusaetzlich"
  gewuenscht). (2) "Nach Farbidentitaet" - `_bucketSection` hat einen
  neuen Parameter `showManaSymbols` (nur fuer diesen Aufruf gesetzt,
  die anderen beiden Aufrufe fuer Startposition/Partiendauer bleiben
  unveraendert bei reinem Text, da deren Labels keine Farben sind).
  Da `BucketWinStats.label` bei diesem Bucket entweder eine reine
  WUBRG-Farbidentitaet ODER der Sammel-Text 'Kein Deck angegeben'
  ist (siehe `computeWinRateByColorIdentity` - fasst dort bewusst
  farblose Decks UND Partien ganz ohne Deck-Angabe zusammen, eine
  bereits bestehende Ungenauigkeit, hier nicht angefasst), prueft
  ein neuer `_wubrgOnly`-RegExp (`^[WUBRG]+$`) vor der Symbol-
  Anzeige, ob das Label ueberhaupt eine Farbe ist - beim Sammel-Text
  bleibt es bei reinem Text ohne (irrefuehrendes) Symbol.

- **Elo-Barometer im Statistik-Screen** (Nutzerwunsch: das vom
  Home-Dashboard bekannte Barometer, siehe `ScoreGauge`
  (`core/widgets/score_gauge.dart`) und `EloScoreCard`
  (`home/view/widgets/elo_score_card.dart`), auch im Statistik-Tab
  einsetzen). Die bisherige reine Text-Anzeige ('${elo.score0to100}
  / 100') in der "Elo-Score"-Karte von `stats_screen.dart` wurde
  durch `Center(child: ScoreGauge(score: elo.score0to100, label:
  eloScoreLabel(elo.score0to100)))` ersetzt - Beschreibungstext
  darunter unveraendert (nur zentriert). Bewusst weiterhin die
  GEFILTERTE `elo`-Berechnung dieses Screens (`computeEloScore
  (filtered)`, respektiert Gruppen-/Modus-Auswahl) statt der
  ungefilterten Variante von `EloScoreCard` auf dem Home-Tab - siehe
  deren Klassendoku ("im Unterschied zur filterbaren Elo-Anzeige auf
  dem Statistik-Tab").

- **Deck-Suche im Decks-Screen** (Nutzerwunsch: wieder Decks
  durchsuchen koennen, sowohl nach Deck-Name als auch nach
  Commander-Name - bewusst enger gefasst als das Vorbild in
  mtg_stats_tracker, das dort zusaetzlich noch Besitzer, Farb-
  identitaet und Deck-Typ durchsuchte). `PlayerDetailScreen` hat
  jetzt ein Such-Symbol in der AppBar (`_showSearch`), das ein
  Suchfeld ein-/ausblendet; die Filterung (`_searchQuery`) laeuft
  rein lokal auf der bereits geladenen Deck-Liste (kein neuer
  Riverpod-Provider noetig, anders als `deckSearchProvider` im
  Vorgaenger) - verglichen werden `deck.name`,
  `deck.commanderName` und `deck.secondCommanderName`, alle
  klein geschrieben und als Teilstring-Suche (`contains`). Body
  dafuer von `decksAsync.when(...)` direkt auf
  `Column(children: [Suchfeld, Expanded(child: decksAsync.when(...))])`
  umgestellt.

- **Dunkler Hintergrund fuer das weisse Mana-Symbol**
  (Nutzer-Feedback: das helle Symbol war auf dem neutralen hellen
  Standard-Hintergrund von `ManaSymbol` kaum zu erkennen). Nur die
  Farbe 'W' bekommt jetzt ueber `_backgroundFor` einen eigenen
  dunklen Kreis-Hintergrund (`_darkCoinColor`, `0xFF2A2622`), alle
  anderen Mana-Farben bleiben beim bisherigen hellen `_coinColor`.

- **Echte Mana-Symbole in der Farbidentitaets-Auswahl** (Nutzerwunsch:
  in `ColorIdentityPicker`, siehe `deck_form_dialog.dart`, sollten wie
  in mtg_stats_tracker echte Mana-Symbole statt nur Text stehen).
  `mana_icons_flutter` war bereits als Abhaengigkeit in pubspec.yaml
  vorhanden (vermutlich 1:1 beim Projekt-Setup aus
  mtg_stats_tracker uebernommen), aber bislang nirgends im Code
  genutzt - keine pubspec-Aenderung noetig. Neu:
  `lib/core/widgets/mana_symbol.dart` (`ManaSymbol`, ein WUBRG-
  Buchstabe -> farbiges Mana-Icon auf neutralem Kreis-Hintergrund,
  bewusst theme-unabhaengig gehalten wie `manaIconBackgroundColor`
  im Vorgaenger, damit z. B. Weiss auf hellem Parchment-Theme nicht
  verschwindet; nutzt dieselbe Mana-Farbpalette wie der
  Kartenstapel-Look, siehe mana_colors.dart, fuer ein einheitliches
  Farbbild). `ColorIdentityPicker` zeigt das Symbol jetzt als
  `FilterChip`-Avatar VOR dem Farbnamen; `showCheckmark: false`
  gesetzt, da Material-Chips den Avatar sonst im ausgewaehlten
  Zustand durch ein Haekchen ersetzen wuerden - das Symbol soll aber
  gerade dann sichtbar bleiben, Auswahl bleibt weiterhin ueber
  Chip-Hintergrund/-Rand erkennbar.

- **Kartenstapel-Look im Decks-Screen** (Nutzerwunsch: die Deck-Liste
  im Decks-Tab, `PlayerDetailScreen`, sollte wie in der alten App
  mtg_stats_tracker aussehen, als "wuerden die Karten der jeweiligen
  Commander uebereinander liegen" - beim Nachsehen in
  mtg_stats_tracker gab es dafuer aber keine fertige Vorlage: dort
  existieren gar keine echten Kartenbilder (kein Scryfall-Abruf, kein
  entsprechendes Datenfeld, auch nicht in der gesamten Git-Historie),
  nur ein nie fertiggestellter leerer `Stack`-Rest
  (`// Dein bisheriger Stack-Inhalt`) in `deck_card.dart`/
  `deck_card_old.dart`. Mit dem Nutzer abgestimmt: rein dekorativer
  Stapel-Effekt statt echter Kartenbilder. Neu:
  `lib/core/utils/mana_colors.dart` (WUBRG-Buchstabe ->
  `Color`, angelehnt an die physischen Magic-Kartenfarben, unabhaengig
  von der App-Akzentfarbe) und
  `lib/features/decks/view/widgets/deck_stack_card.dart`
  (`DeckStackCard`, ersetzt das bisherige `ListTile` 1:1 in der
  Funktion - Titel/Untertitel/Trailing/Tap/Archiviert-Abdunklung
  bleiben wie zuvor). Optisch: zwei leicht rotierte/versetzte
  "Kartenruecken" (Gradient aus den Mana-Farben der
  `colorIdentity`, farbloses Deck = Grauton) liegen hinter der
  eigentlichen Info-Kachel; die Info-Kachel selbst bekommt zusaetzlich
  einen schmalen farbigen Rand-Streifen in denselben Farben, um sie
  optisch mit dem Stapel zu verbinden. Nutzt weiterhin die
  Vault & Foil-Theme-Farben (`colorScheme.surfaceContainer`/
  `outlineVariant`/`primary`) fuer Kachel-Hintergrund, -Rand und
  Foil-Akzent der Kartenruecken-Raender, statt eigener Theme-fremder
  Farbwerte. Vorerst nur im Decks-Tab (`PlayerDetailScreen`)
  eingesetzt, `DeckStackCard` ist aber bewusst generisch gehalten
  (Name/Untertitel/Farbidentitaet/Trailing/Tap als Parameter statt des
  konkreten `Deck`-Modells) und liesse sich bei Bedarf auch an anderen
  Deck-Listen-Stellen (z. B. Auswahl-Dialoge) wiederverwenden.

- **Anzahl-Erreichungen bei Sieg-/Wochentags-Serien** (Nutzerhinweis:
  einige Badges lassen sich mehrfach "erarbeiten" - Sieg-Serien und
  Wochentags-Serien -, dafür zusätzlich gewünscht, wie oft das bereits
  vorkam). `AchievementStatus`
  (`lib/features/achievements/model/achievement_status.dart`) trägt
  jetzt ein neues Feld `timesAchieved` (int?, NUR bei diesen beiden
  Kategorien gesetzt, sonst null). `_computeStreaks`/`_computeWeekday`
  in `achievement_engine.dart` zählen jetzt mit, wie oft eine Serie
  GENAU die jeweilige Schwellenlänge erreicht hat (jede Serie
  durchläuft jede Schwelle beim Hochzählen genau einmal - ein erneutes
  Erreichen nach einem Reset zählt als weiteres Mal), zusätzlich zum
  bereits vorhandenen `achievedAt` (weiterhin der ZULETZT erreichte
  Zeitpunkt). `BadgeTile` zeigt bei gesetztem `timesAchieved`
  zusätzlich eine dritte Zeile "N× erreicht" unter Titel/Datum (auch
  im Tooltip ergänzt). Da `LastAchievementsCard` bisher nur
  `MapEntry<BadgeDefinition, DateTime>` durchreichte, wurde das dort
  auf ein Record `(BadgeDefinition, DateTime, int?)` umgestellt, um
  `timesAchieved` mitzuführen.

- **Bezeichnung (Spezial-Badges) + Freischalt-Datum (ALLE Badges)
  sichtbar unter der Kachel** (Nutzerhinweis: im mtg_stats-Original
  stand unter jedem Badge eine Bezeichnung sowie - sobald
  freigeschaltet - das Datum; zunächst zumindest für die Spezial-
  Badges ergänzt, auf Nachfrage dann das Datum für ALLE Badges
  nachgezogen: "das Datum des zum letzten Mal Erreichens"). `BadgeTile`
  (`lib/features/achievements/view/widgets/badge_tile.dart`) zeigt
  jetzt zweistufig sichtbar UNTER der Icon-Kachel statt nur im (leicht
  zu übersehenden) Tooltip:
  - Titel: nur bei `BadgeCategory.special` (immer, auch gesperrt - man
    sieht so, was noch zu erreichen ist) - die übrigen Kategorien
    (Serien, Partien, Siege, Farbchampion, Wochentag) haben je
    deutlich mehr Einträge, ein Titel unter jeder Kachel hätte das
    Grid dort stark aufgebläht.
  - Freischalt-Datum: bei ALLEN Kategorien, sobald `unlocked &&
    achievedAt != null` - bei Serien-Badges ist das bereits der
    ZULETZT erreichte Zeitpunkt (siehe achievement_status.dart), passt
    also direkt zur Nutzeranforderung. Gesperrte Badges zeigen
    weiterhin nur die (abgeblendete) Icon-Kachel ohne jeden Zusatztext
    - Layout dafür unverändert zum Ursprungszustand.
  Der Tooltip bleibt für Titel+Datum aller Badges als vollständige
  Zusatzinfo bestehen. Da sowohl `AchievementsScreen` als auch die
  "Deine letzten Erfolge"-Karte im Home-Dashboard dieselbe `BadgeTile`-
  Komponente in einem ungebundenen `Wrap` nutzen, wirkt die Änderung
  an beiden Stellen ohne weitere Anpassung.

- **Archivierte Daten sichtbar/reaktivierbar gemacht** (Nutzerfrage
  "Wie sehe ich archivierte Daten?" - Antwort war: gar nicht, denn
  Archivieren war eine Einbahnstraße. Jede Liste
  (`playerDecksProvider`, `allActivePlayersProvider`,
  `allGroupsProvider`) filterte hart auf `archived == false`, es gab
  weder einen Filter/Umschalter noch eine "Reaktivieren"-Option in den
  Bearbeiten-Dialogen - einmal archiviert war ein Eintrag faktisch
  unerreichbar):
  - **Decks** (`PlayerDetailScreen`): neuer Umschalter (Archiv-Symbol
    in der AppBar) zeigt zusätzlich archivierte Decks an (neue
    `DecksRepository.watchAllDecksForPlayer`/`allPlayerDecksProvider`,
    ungefiltert), archivierte Decks abgeblendet (`Opacity` 0.6) und
    mit "archiviert" im Untertitel markiert. `deck_form_dialog.dart`:
    der bisherige reine "Deck archivieren"-Button ist jetzt ein
    Umschalter (zeigt "Deck reaktivieren", wenn `existingDeck.archived
    == true`).
  - **Gruppen** (`GroupsOverviewScreen`): derselbe Umschalter (neue
    `GroupsRepository.watchAll`/`allGroupsIncludingArchivedProvider`,
    ungefiltert), archivierte Gruppen abgeblendet und mit "·
    archiviert" markiert. `GroupDetailScreen`: "Archivieren" im
    Popup-Menü ist jetzt ebenfalls ein Umschalter - beim Archivieren
    wie bisher zurück zur Übersicht, beim Reaktivieren bewusst auf der
    Detailseite bleiben.
  - **Spieler**: da es (bewusst, siehe `main_shell.dart`) keine eigene
    Spielerübersicht gibt, sind Spieler ausschließlich über
    Gruppenmitgliedschaften erreichbar. `GroupDetailScreen`s
    Mitgliederliste (`watchMembers`) war schon immer ungefiltert -
    archivierte Mitglieder erscheinen jetzt zusätzlich abgeblendet mit
    "Archiviert · ..." im Untertitel. `PlayerDetailScreen`s
    "Archivieren" im Popup-Menü ist jetzt ebenfalls ein Umschalter
    ("Reaktivieren", wenn bereits archiviert; Bildschirm wird nur beim
    Archivieren verlassen). Für einen archivierten Spieler, der
    aktuell in KEINER Gruppe mehr Mitglied ist, gibt es weiterhin
    keine eigene Übersicht (bewusst keine neue Archiv-Ansicht) -
    stattdessen bekommt der "Mitglied hinzufügen"-Dialog in
    `GroupDetailScreen` eine Checkbox "Archivierte Spieler einbeziehen"
    (neue `PlayersRepository.watchAll`-Provider
    `allPlayersIncludingArchivedProvider`, `watchAll` existierte
    bereits ungenutzt in der Repository) - erneutes Hinzufügen macht
    ihn über die Mitgliederliste wieder sichtbar/reaktivierbar, ohne
    dass das Archivieren selbst dadurch aufgehoben wird.

- **Umlaute beim Datei-Import verstümmelt** (Nutzerhinweis: Umlaute in
  der Import-Datei werden nicht korrekt angezeigt). Ursache in
  `ImportWizardScreen._pickFile`
  (`lib/features/import/view/screen/import_wizard_screen.dart`): die
  vom `file_picker` gelieferten rohen Bytes wurden mit
  `String.fromCharCodes(bytes)` in einen String gewandelt - das bildet
  jedes Byte 1:1 auf einen UTF-16-Codepoint ab statt Mehrbyte-UTF-8-
  Sequenzen zu decodieren, wodurch ä/ö/ü/ß (2 Byte in UTF-8) als zwei
  falsche Zeichen erschienen. Betraf nur den Datei-Import - der
  QR-Import bekommt vom Scanner bereits einen fertig decodierten
  String, und der Export (`ExportWizardScreen`) nutzt bereits korrekt
  `utf8.encode`/`File.writeAsString` (Standard-Encoding utf8). Behoben
  durch `utf8.decode(bytes)` (`dart:convert`) statt
  `String.fromCharCodes(bytes)`.

- **"Ehrenwerte Niederlage"-Badge reaktiviert** (Nutzerhinweis: da
  Deck-Verleih jetzt technisch möglich ist, müsste auch das
  `shame`-Badge - Niederlage gegen einen Gegner, der dabei ein
  EIGENES Deck des Ich-Spielers spielt - wieder erreichbar sein; war
  zuvor bewusst dauerhaft gesperrt, siehe "Aktueller Stand / nächste
  Schritte"). `SelfGameStatsRow` (`games_repository.dart`) trägt jetzt
  zusätzlich `opponentPlayedOwnDeck` (true, wenn in dieser Partie ein
  ANDERER Teilnehmer ein Deck spielt, dessen `Decks.ownerPlayerId` der
  Ich-Spieler ist - unabhängig davon, wer laut Startaufstellung
  eigentlich "der Besitzer" ist) - berechnet in `watchSelfGameStats`
  aus den ohnehin schon je Partie geladenen Teilnehmer-Zeilen, kein
  zusätzlicher Datenbank-Zugriff nötig. `achievement_engine.dart`
  schaltet `shame` jetzt bei der frühesten ECHT verlorenen Partie
  (weder Sieg noch Unentschieden) mit `opponentPlayedOwnDeck == true`
  frei, analog zum first_win/first_strike-Muster.

- **Import: automatische Gruppen-Zuordnung + zusammengefasste
  Hinweise** (Nutzeranforderung, Ergänzung zum Import-Assistenten):
  - **Automatische Gruppen-Zuordnung**: Gehören ALLE Teilnehmer einer
    zu importierenden Partie in der App bereits gemeinsam einer
    EINDEUTIGEN Gruppe an, wird die Partie jetzt automatisch dieser
    Gruppe zugeordnet - auch wenn das Bundle selbst keine (oder keine
    lokal auflösbare) Gruppe angibt. Umgesetzt in
    `ImportService.performImport` (`inferSharedGroupId`): Teilnehmer
    werden jetzt VOR dem Anlegen der Partie aufgelöst (statt wie
    bisher erst beim Einfügen), damit die Gruppen-Zuordnung schon die
    aufgelösten Spieler-ids kennt. Getroffene Annahmen (nicht extra
    erfragt, da mechanische Implementierungsdetails): (1) greift nur,
    wenn ALLE Teilnehmer bekannten lokalen Spielern entsprechen - ist
    auch nur EIN Teilnehmer anonym, wird keine Gruppe geraten; (2) die
    im Bundle angegebene Gruppe (`GameExport.groupName`) hat Vorrang,
    die Automatik greift nur als Fallback, wenn die Partie danach
    weiterhin ohne Gruppe wäre; (3) "eindeutig" heißt: der Schnitt der
    Gruppen-Mitgliedschaften aller Teilnehmer enthält GENAU eine
    Gruppe - bei 0 oder mehreren gemeinsamen Gruppen wird bewusst
    nichts zugeordnet statt einer Willkür-Wahl.
  - **Zusammengefasste Hinweise statt Einzelliste**: Die "Hinweise" im
    Ergebnis-Schritt des Import-Wizards (z. B. "Deck X übersprungen:
    Besitzer nicht importiert/gefunden") erscheinen nicht mehr als
    lange Einzelliste, sondern je Kategorie zusammengefasst (z. B. "3
    Decks nicht importiert", "2 Teilnehmer als anonym übernommen"),
    mit Möglichkeit die Original-Meldungen pro Kategorie aufzuklappen
    (`_WarningGroupTile`, ein `ExpansionTile` je Kategorie, in
    `import_wizard_screen.dart`). Dafür trägt `ImportResult.warnings`
    jetzt `ImportWarning`-Objekte (`category` + `message`, neue Datei
    `import_warning.dart`) statt roher Strings - Kategorien:
    `deck`/`participant`/`game`.

- **Deck-Verleih (Decks eines anderen Spielers spielen) + Import des
  mtg_stats-Datenabzugs** (Nutzeranforderung: historische Daten aus
  der Vorgänger-App mtg_stats importieren - dabei fiel auf, dass 16
  reale Partien-Teilnahmen ein Deck nutzen, das laut Deck-Liste einem
  ANDEREN Spieler gehört ("Deck-Verleih"); die App ging bis dahin
  strukturell davon aus, dass das nie vorkommen kann (siehe Kommentar
  zum "Schande"-Achievement). Der Nutzer wünschte deshalb echte
  Deck-Verleih-Unterstützung statt eines reinen Notiz-Workarounds):
  - **UI**: `AddKnownParticipantDialog`
    (`lib/features/games/view/widgets/add_known_participant_dialog.dart`)
    und `SelectDeckDialog`
    (`lib/features/games/view/widgets/select_deck_dialog.dart`) haben
    unten in der (unveränderten) eigenen Deck-Liste jetzt einen
    zusätzlichen Eintrag "Geliehenes Deck (von einem anderen
    Spieler)" (mit dem Nutzer abgestimmte Variante) - tippt man ihn
    an, öffnet sich ein Zwischenschritt zur Auswahl des Verleihers
    (alle bekannten Spieler außer dem Teilnehmer selbst) und danach
    eines von dessen Decks. Der Normalfall (eigenes Deck) bleibt
    optisch unverändert.
  - **Datenmodell**: kein Migrations-Bedarf -
    `GameParticipants.deckId` hatte schon nie eine Besitzer-
    Einschränkung (bloße nullable FK auf `Decks.id`), die Beschränkung
    auf eigene Decks existierte ausschließlich in der UI. Ein
    Deck-Verleih ist beim Lesen bereits allein am Vergleich von
    `GameParticipants.playerId` mit `Decks.ownerPlayerId` erkennbar
    (siehe `games_repository.dart`) - daher trägt
    `GameParticipantDraft` die geliehene Zuordnung nur übergangsweise
    während der Erfassung als `deckOwnerPlayerId`/`deckOwnerName`
    (rein informativ, u. a. für den "(geliehen von X)"-Hinweis in der
    Teilnehmer-Karte auf dem Partien-Setup-Screen). Eine entsprechende
    Anzeige in der Partien-Detailansicht (`GameParticipantView`) ist
    noch nicht umgesetzt (bräuchte einen zweiten Join auf `Players`
    für den Deck-Besitzer) - möglicher Folgeschritt, aktuell nicht
    beauftragt.
  - **Export/Import**: `GameParticipantExport.deckOwnerName` (neu,
    siehe Export/Import-Abschnitt oben) trägt den Deck-Besitzer beim
    Datei-/QR-Export/Import mit, `ImportService` löst den Deck-
    Schlüssel jetzt über `deckOwnerName ?? playerName` auf.
  - **mtg_stats-Import**: `convert_mtg_stats_export.py` (Migrations-
    Skript, nicht Teil der App) wandelt `export_2026-09-07.json` (81
    mtg_stats-Datenabzug: 11 Spieler, 70 Decks davon 2 inaktiv -> als
    `archived` importiert (mit dem Nutzer abgestimmt), 78 Partien
    davon 2 Two-Headed-Giant, 259 Teilnahmen) in
    `mtg_stats_import_2026-09-07.json` (Track & Play `ExportBundle`-
    Format) um, bereit zum Einlesen über den bestehenden Import-
    Assistenten ("Daten importieren" in den Weiteren Optionen) - der
    erledigt die interaktive Namens-Zuordnung/Duplikat-Erkennung/
    Anonym-Fallback bereits vollständig, es musste nur das
    Datenformat konvertiert werden. Die 16 Deck-Verleih-Fälle (in 12
    Partien) werden dank obiger Deck-Verleih-Unterstützung jetzt
    korrekt verlinkt statt gedroppt. Two-Headed-Giant-Besonderheit:
    mtg_stats' `startPosition` codiert dort die TEAM-Zugehörigkeit
    (1/2, von beiden Team-Mitgliedern geteilt), nicht die echte
    Zugreihenfolge - beim Import wird das auf das `team`-Feld
    ("A"/"B") gemappt, die echte `startPosition` bleibt für 2HG-
    Teilnehmer bewusst `null` (nicht rekonstruierbar). Fehlende Felder
    (Partiendauer, First Blood, Startleben) werden wie besprochen als
    `null` übernommen, zwei Datenqualitäts-Eigenheiten der Quelle
    (uneinheitliche `startPosition`/gleiche `placement`-Werte in
    wenigen Partien) wurden bewusst unverändert übernommen statt
    "korrigiert".

- **Reminder auch bei "noch nie gespielt"** (Nutzerfrage: deckt die
  Erinnerung auf dem Home-Dashboard auch den Fall ab, dass noch NIE
  eine Partie gespielt wurde, oder nur "letzte Partie >= 1 Tag her"?
  Antwort war bis dahin: nur Letzteres - bei `rows.isEmpty` wurde die
  Karte komplett ausgeblendet statt zu ermuntern). Ergänzt in
  `LastGameReminderCard`
  (`lib/features/home/view/widgets/last_game_reminder_card.dart`): bei
  `rows.isEmpty` erscheint jetzt "Bereit für deine erste Partie? Du
  hast noch keine Partie erfasst - leg los!" statt der Karte "Vermisst
  du es schon?". Gemeinsame Card-Optik in `_buildCard(...)`
  extrahiert, damit beide Texte dieselbe Aufmachung (Icon + Titel +
  Untertext) nutzen, statt sie zu duplizieren.

- **"Mitspieler tracken" nachträglich umschaltbar** (Nutzerfrage: der
  Setup-Wizard verspricht "Das lässt sich später jederzeit in den
  Einstellungen ändern", es gab dafür aber noch KEINE UI - die einzige
  Stelle, die `AppSettings.trackOtherPlayers` je gesetzt hat, war der
  einmalige Setup-Wizard selbst über
  `SettingsController.setTrackOtherPlayersAndSelf`). Nachgerüstet als
  weiterer Eintrag in der "Weitere Optionen"-Card auf dem Home-
  Dashboard (`_QuickLinksCard` in `home_screen.dart`, jetzt ein
  `ConsumerWidget` statt `StatelessWidget` - `showGroups` wurde von
  einem übergebenen Parameter zu einem selbst beobachteten
  `settingsControllerProvider`-Wert): ein `SwitchListTile` "Mitspieler
  tracken" ganz unten in der Card. Neue Methode
  `SettingsController.setTrackOtherPlayers(bool)`
  (`app_settings_provider.dart`) - im Unterschied zu
  `setTrackOtherPlayersAndSelf` (Setup-Wizard, legt `selfPlayerId` neu
  fest) übernimmt sie den bereits vorhandenen `selfPlayerId`
  unverändert aus dem aktuellen State (`AppSettings.copyWith`). Rein
  additiv/nicht destruktiv: bestehende Gruppen/Mitspieler-Daten bleiben
  beim Ausschalten in der Datenbank erhalten, nur die zugehörigen
  UI-Bereiche (Gruppen verwalten, Team-/Gruppenauswahl bei Partien,
  Gruppen-Filter im Statistik-Dashboard) werden je nach Wert reaktiv
  ein-/ausgeblendet, da sie alle bereits auf
  `settingsControllerProvider` reagieren. Keine Sicherheitsabfrage
  beim Ausschalten (bewusst, da nichts gelöscht wird und der Schalter
  jederzeit wieder umgelegt werden kann).

- **Elo-Score als Barometer im Home-Dashboard** (auf Nutzerwunsch,
  angelehnt an "PlayerScore"/"Speedometer" aus mtg_stats_tracker -
  dort für einen anderen, eigenen "Dominance"-Score genutzt): neue
  Karte `EloScoreCard`
  (`lib/features/home/view/widgets/elo_score_card.dart`) zeigt den
  bereits für das Statistik-Dashboard vorhandenen `computeEloScore`
  (`lib/features/stats/model/player_performance_stats.dart`) als
  rundes Zeiger-Barometer statt reinem Text. Bewusst UNGEFILTERT nach
  Gruppe/Modus (wie die Achievements, siehe achievement_engine.dart) -
  anders als die filterbare Elo-Anzeige auf dem Statistik-Tab, die
  unverändert bleibt. Neue, wiederverwendbare Komponente
  `ScoreGauge` (`lib/core/widgets/score_gauge.dart`, `CustomPainter`) -
  die Geometrie (270°-Bogen, Ticks, Marker-Punkt) ist 1:1 aus
  `SpeedometerPainter` von mtg_stats_tracker übernommen, ABER die
  Farben kommen bewusst aus dem App-Theme (`scheme.primary` für den
  Wert-Bogen, `scheme.outlineVariant` für Hintergrundring/Ticks) statt
  hartcodiertem Weiß wie im Original - Vault & Foil funktioniert damit
  theoretisch auch im (aktuell ungenutzten) hellen Modus. Neues
  Textlabel `eloScoreLabel` (in `player_performance_stats.dart`, 1:1
  von `playerDominanceLabel` übernommene Schwellenwerte, da beide
  Scores 0-100 mit 50 = durchschnittlich sind). Card wird ausgeblendet,
  wenn der Ich-Spieler noch keine Partien hat (analog zu den anderen
  Dashboard-Karten).

- **Badge-Kacheln vergrößert** (Nutzer-Feedback: "in Summe etwas
  größer", sowohl im Home-Dashboard als auch in der Erfolge-Übersicht):
  da beide Stellen seit dem Refactoring (siehe "Home-Dashboard mit
  Gamification" unten) dieselbe `BadgeTile`-Komponente
  (`lib/features/achievements/view/widgets/badge_tile.dart`) nutzen,
  genügte eine zentrale Änderung dort - Container von 48x48 auf 64x64
  angehoben, Padding von 4 auf 6, Eckenradius von 6 auf 8. Wirkt
  automatisch an beiden Stellen.

- **"Weitere Optionen"-Card statt einzelner Buttons** (auf
  Nutzerfrage nach einer "eleganteren Möglichkeit" für Export/Import/
  Gruppen verwalten): die drei bisherigen einzelnen, volle Breite
  einnehmenden `OutlinedButton.icon` ganz unten auf dem Home-Dashboard
  wurden durch eine einzelne Card mit kompakter, Settings-artiger
  Zeilenliste ersetzt (`_QuickLinksCard`/`_QuickLinkItem`, unten in
  `home_screen.dart`) - Icon + Text + Pfeil pro Zeile, durch
  `Divider(height: 1)` getrennt. Per Rückfrage mit drei Alternativen
  (Liste in einer Card / Icon-Kachel-Reihe / Overflow-Menü in der
  App-Bar) abgestimmt - der Nutzer entschied sich für die Listen-
  Variante, da sie alle drei Optionen weiterhin ohne zusätzlichen Tap
  sichtbar hält. "Gruppen verwalten" bleibt weiterhin nur sichtbar,
  wenn `AppSettings.trackOtherPlayers == true` (jetzt über den
  `showGroups`-Parameter der Card statt über ein eigenes
  `settingsAsync.when` je Button).

- **Home-Dashboard mit Gamification** (auf Nutzerwunsch, Umsetzung von
  "Noch zu bauen" Punkt 1 "Home-Tab zu einem echten Dashboard
  ausbauen"): der Nutzer wollte die Gamification-Elemente aus dem
  mtg_stats_tracker-Home-Screen zurück - konkret vier Bausteine, die
  Reihenfolge unten entspricht der Reihenfolge im UI:

  1. **Begrüßung** - unverändert (`Willkommen zurück, ...!`), nur die
     Layout-Struktur des Screens wurde angepasst (siehe unten).
  2. **Erinnerung an die letzte Partie**
     (`lib/features/home/view/widgets/last_game_reminder_card.dart`) -
     angelehnt an "DaysSinceLastGame" aus mtg_stats_tracker, dort aber
     ab Tag 0 sichtbar ("Heute vielleicht noch eine weitere Runde?").
     Der Nutzer wollte die Karte EXPLIZIT erst AB MINDESTENS EINEM TAG
     zeigen, deshalb wurde die Tag-0-Variante bewusst weggelassen -
     `_daysSince(...) < 1` blendet die Karte komplett aus. Letztes
     Partien-Datum wird aus `selfGameStatsProvider` (bereits für das
     Statistik-Dashboard vorhanden) als `rows.map(playedAt).reduce(max)`
     berechnet, kein neuer Provider nötig.
  3. **Random-Deck-Funktion**
     (`lib/features/home/model/random_deck_filter_state.dart`,
     `lib/features/home/controller/provider/random_deck_filter_
     provider.dart` + `random_deck_provider.dart`,
     `lib/features/home/view/widgets/random_deck_card.dart` +
     `random_deck_filter_sheet.dart`) - auf Nachfrage entschied sich
     der Nutzer für die VOLLE Variante MIT Filtern (Bracket 1-5, Art
     des Decks Precon/Aufgewertet/Eigenbau, Proxy ja/nein) statt eines
     einfachen Buttons ohne Filter, da das Deck-Modell hier dieselben
     Felder wie im Original hat (`bracket`/`buildType`/`isProxy`,
     siehe `deck_form_dialog.dart`) - 1:1 aus mtg_stats_tracker
     übernommen (`RandomDeck`/`RandomDeckFilterState`/
     `RandomDeckFilterBottomSheet`), nur die Filter-Notifier-API
     bewusst OHNE nullable `copyWith`-Parameter (siehe Kommentar in
     `random_deck_filter_provider.dart` - explizite Setter-Methoden
     statt `copyWith(int? bracket)`, das "nicht ändern" und "auf null
     setzen" nicht sauber unterscheiden könnte). Nutzt bewusst nur die
     Decks des Ich-Spielers (`playerDecksProvider`), nicht mtg_stats'
     "focusPlayer"-Konzept - dafür gibt es hier kein Äquivalent. Icon
     für den Würfel-Button: `Icons.shuffle` (Material-Standard) statt
     des `icomoon`-Custom-Icons aus dem Original, das hier nicht
     verfügbar ist.
  4. **Vorschau der letzten Erfolge**
     (`lib/features/home/view/widgets/last_achievements_card.dart`) -
     angelehnt an "LastArchievements" aus mtg_stats_tracker: zeigt die
     zuletzt freigeschalteten Badges (aus `computeAchievements`,
     absteigend nach `achievedAt` sortiert) mit einem Link/Zähler zum
     vollständigen `AchievementsScreen`. Nutzer nannte "drei oder vier"
     Badges als gleichwertig - bewusst 4 gewählt (`_maxShown = 4` in
     der Datei). Der bisher eigenständige "Meine Erfolge"-Button auf
     dem Home-Screen wurde entfernt, da er mit dieser Karte redundant
     geworden ist (deren Zähler-Link denselben Zugang bietet) - genau
     wie im Original, das ebenfalls keinen separaten Quick-Access-
     Button dafür hatte.

  **Refactoring dabei:** die private `_BadgeTile` aus
  `achievements_screen.dart` wurde in eine wiederverwendbare
  `BadgeTile`-Komponente ausgelagert
  (`lib/features/achievements/view/widgets/badge_tile.dart`), damit
  die neue Erfolge-Karte dieselbe Optik (48x48-Kachel, Tooltip mit
  Name + Datum, Ausgrauen bei `unlocked: false`) nutzt, statt sie zu
  duplizieren. `AchievementsScreen` verwendet jetzt ebenfalls diese
  gemeinsame Komponente.

  **Layout-Änderung in `home_screen.dart`:** der Screen-Body wurde von
  `Center` + `Column(mainAxisSize: MainAxisSize.min)` (passend für
  eine kurze, immer auf den Screen passende Button-Liste) auf
  `SingleChildScrollView` + `Column(crossAxisAlignment:
  CrossAxisAlignment.stretch)` umgestellt, da die neuen Dashboard-
  Karten den Platz auf kleineren Screens sprengen und außerdem über
  die volle Breite gehen sollen (`stretch` lässt auch die
  Export/Import/Gruppen-Buttons jetzt volle Breite einnehmen statt nur
  ihre Inhaltsbreite - keine bewusste Stil-Entscheidung, sondern
  Nebeneffekt der Umstellung, die "optische Aufbereitung" bleibt
  weiterhin bewusst auf ganz zuletzt verschoben, siehe "Noch zu
  bauen").

- **Screen-Überschriften app-weit golden** (auf Nutzerwunsch, Nachtrag
  zum App-Header): nachdem nur der Home-Header golden war, wollte der
  Nutzer das auch für die übrigen Screen-Titel ("Meine Statistik",
  "Decks" bzw. Spielername, "Partien" usw.). Statt jede der 14
  `AppBar`-Stellen im Code einzeln anzufassen, wurde das zentral in
  `AppTheme._build` gelöst: `AppBarTheme.titleTextStyle` ist jetzt
  `textTheme.titleLarge?.copyWith(color: scheme.primary, fontSize: 30)`
  (Cinzel + Gold + Größe 30, siehe Nachtrag unten), `foregroundColor` bleibt separat auf `scheme.onSurface` -
  damit werden nur die Titel-Texte golden, nicht auch Zurück-Pfeil und
  App-Bar-Icons. Screens mit einem einfachen `title: Text('...')` ohne
  eigenen `style:` (das ist app-weit aktuell überall der Fall, siehe
  Grep-Check) erben das automatisch. Der Home-Header
  (`HomeScreen`) wurde dabei vereinfacht: sein Text setzte die
  Gold-Farbe zuvor manuell, das war nach dieser Änderung redundant und
  wurde entfernt - dort steht jetzt nur noch Logo + einfacher
  `Text('Track & Play')`.

  **Stolperstein dabei:** `Row(children: const [Image.asset(...), ...])`
  kompiliert nicht - `Image.asset(...)` ist kein `const`-Konstruktor
  (lädt das Asset zur Laufzeit), im Gegensatz zum einfachen `Image(image:
  AssetImage(...))`, der es ist. Der Home-Header nutzt deshalb bewusst
  `Image(image: AssetImage('assets/icon/tap_icon_fg.png'), height: 48)`
  statt `Image.asset(...)`, damit die `children`-Liste komplett `const`
  bleiben kann.

  **Nachtrag (Schriftgröße):** die Größe 30 wurde erst nur lokal am
  Home-Header gesetzt (siehe "App-Header: Logo + Gold-Schriftzug"
  unten), weil der Nutzer zunächst nur den Home-Header als "viel zu
  klein" bemängelt hatte. Als er kurz danach meldete, dass auch
  Decks/Statistik/Partien noch zu klein wirken, wurde per Rückfrage
  geklärt, ob nur diese drei Tabs oder wirklich alle Screen-Titel
  betroffen sein sollen - Antwort: **app-weit für alle Screens.**
  Seitdem steht die 30 hier zentral in `AppBarTheme.titleTextStyle`
  und gilt automatisch für jeden `AppBar`-Titel in der App, nicht nur
  für die vier Bottom-Nav-Tabs.

- **App-Header: Logo + Gold-Schriftzug** (auf Nutzerwunsch, Nachtrag
  zum "Vault & Foil"-Theme): der "Track & Play"-Titel im App-Bar des
  Home-Tabs sollte die Cinzel-Schriftart behalten, aber in Gold statt
  der Standard-Textfarbe stehen, UND das App-Logo sollte mit im Header
  auftauchen - genau wie im mtg_stats_tracker-Vorgänger, dessen
  `home_screen.dart` exakt dieses Muster hatte (`tap_icon_fg.png` +
  Text in einer `Row` als App-Bar-Titel). Umgesetzt in
  `HomeScreen` (Home-Tab der Bottom Navigation, siehe unten): `title`
  ist jetzt eine `Row` aus `Image.asset('assets/icon/tap_icon_fg.png',
  height: 48)` (das bereits für den Splash-Screen genutzte, transparente
  Gold-"TAP"-Schriftzugbild, war schon in der pubspec.yaml als Asset
  registriert) plus dem Text "Track & Play" mit
  `textTheme.titleLarge?.copyWith(color: colorScheme.primary)` - die
  Cinzel-Schriftart/Größe/Gewicht bleiben also exakt wie zuvor
  (weiterhin von `titleLarge` geerbt), nur die Farbe wechselt auf Foil-
  Gold. Nur der Home-Tab betroffen, nicht die anderen drei Tabs (deren
  App-Bar-Titel sind funktionale Screen-Titel wie "Meine Statistik",
  kein Marken-Header) und nicht der einmalige Setup-Wizard-Titel
  ("Willkommen bei Track & Play"). Logo-Höhe auf Nutzer-Feedback ("wirkt
  etwas verloren") von ursprünglich 28 auf 48 angehoben, dafür
  zusätzlich `toolbarHeight: 72` (Standard 56) gesetzt, damit im
  höheren Logo genug vertikaler Raum bleibt. Nachtrag 2: Nutzer-Feedback
  ("Schriftart im Header ist viel zu klein") - zunächst wurde die
  Größe nur lokal auf diesem einen `AppBar` per `titleTextStyle`-
  Override auf 30 angehoben, `toolbarHeight` dafür von 72 auf 76
  erhöht. Nachtrag 3: der Nutzer meldete kurz danach, dass auch
  Decks/Statistik/Partien noch zu klein wirken, und entschied sich auf
  Rückfrage für **app-weit alle Screen-Titel auf 30**. Die 30 steht
  seitdem zentral in `AppBarTheme.titleTextStyle` (siehe
  "Screen-Überschriften app-weit golden" oben) - der lokale Override
  hier im `HomeScreen` wurde deshalb als redundant wieder entfernt,
  `toolbarHeight: 76` bleibt aber bestehen, da der 48px-Logo weiterhin
  den zusätzlichen vertikalen Raum braucht (unabhängig von der
  Textgröße).

- **Bottom Navigation Bar** (auf Nutzerwunsch, angelehnt an
  mtg_stats_tracker): der Vorgänger hatte eine schwebende,
  abgerundete Bottom-Nav-Bar mit 5 Tabs (Startseite/Decks/Spieler/
  Partien/Optionen, in `mtg_stats_tracker/lib/features/home/view/
  home_screen.dart`). Track & Play hat aber weder einen eigenen
  "Spieler"-Überblick (nur `PlayerDetailScreen` für einen einzelnen
  Spieler bzw. `GroupsOverviewScreen`) noch einen Optionen-Screen -
  daher keine 1:1-Übernahme, sondern per Rückfrage mit dem Nutzer
  abgestimmt: **4 Tabs - Home / Decks / Statistik / Partien.** Home
  hält dafür die bisherigen "weiteren Aktionen" bereit (Erfolge,
  Export, Import, Gruppen-Verwalten); Decks zeigt `PlayerDetailScreen`
  für den Ich-Spieler; Partien zeigt `GamesOverviewScreen` (der
  vorhandene "+"-FAB dort deckt "Neue Partie erfassen" mit ab, kein
  zusätzlicher Einstieg nötig). Der Nutzer merkte an, dass der
  Home-Tab zeitnah zu einem echten Dashboard ausgebaut werden soll -
  siehe "Noch zu bauen", Punkt 1.

  Umsetzung: neue `MainShell` (`lib/features/home/view/
  main_shell.dart`, `ConsumerStatefulWidget`) ersetzt `HomeScreen` als
  Ziel von `AppRoot` in `main.dart`. Jeder der vier Tabs bleibt ein
  vollständig eigenständiger Screen mit eigenem `Scaffold`/`AppBar`
  statt eines gemeinsamen Shell-AppBars - bewusst so, damit
  `PlayerDetailScreen` und `StatsScreen` unverändert weiter
  funktionieren, wenn sie (wie bisher) auch von ANDEREN Stellen aus
  einzeln gepusht werden (z. B. ein Gruppenmitglied in der
  Gruppen-Detailansicht antippen). `IndexedStack` hält alle vier Tabs
  am Leben (Scroll-/Formular-Zustand bleibt beim Tab-Wechsel
  erhalten). Die Nav-Bar selbst (`_VaultBottomNav`) ist optisch an
  mtg_stats_tracker angelehnt (abgerundete Kapsel-Form mit Schatten,
  schwebend mit Außenabstand), aber in den "Vault & Foil"-Theme-Farben
  statt fest verdrahteter Farben - `colorScheme.primary` für den
  aktiven Tab, `colorScheme.surfaceContainer`/`outlineVariant` für
  Hintergrund/Rahmen. `HomeScreen` selbst wurde entsprechend
  verschlankt: "Neue Partie erfassen"/"Partien-Historie" (jetzt Tab
  Partien), "Meine Statistik" (Tab Statistik) und "Meine Decks" (Tab
  Decks) sind raus, nur noch Erfolge/Export/Import/Gruppen-Verwalten
  bleiben dort.

- **App-Theme "Vault & Foil"** (auf Nutzerwunsch, letzter Punkt 1 der
  "Noch zu bauen"-Liste): der Nutzer wollte einen Theme-Vorschlag, der
  modern/frisch wirkt, thematisch zu Magic the Gathering passt UND das
  Gold des App-Icons als Akzentfarbe aufgreift. Vorgehen: das
  1024x1024-Quellbild des Icons (`assets/icon/tap_icon.png` -
  dunkles Tresor-Petrol mit geprägtem Gold-Schriftzug "TAP") wurde
  über den Geräte-Bridge-Weg (`device_stage_files`/`Read`, da
  `device_bash` keine Bilder anzeigen kann) angesehen, um die
  tatsächlichen Farbtöne zu bestimmen. Daraus wurde ein vollständiger
  Design-Vorschlag als HTML-Artefakt gebaut (Palette, Typografie,
  Mockups der Statistik-Ansicht hell/dunkel, Dart-`ColorScheme`-Skizze)
  und dem Nutzer zur Freigabe vorgelegt, bevor Code geschrieben wurde.

  Nach Freigabe umgesetzt in `lib/core/theme/app_theme.dart`:
  - **Farben:** "Vault" (dunkles Petrol, `#0B1E26`/`#123340`) als
    Grundfarbe im dunklen Modus statt eines generischen Schwarz,
    "Parchment" (warmes Kartenpapier-Creme, `#F6EFDD`/`#EDE1C4`) statt
    sterilem Weiß im hellen Modus, "Foil" (`#D9A441` hell / `#F4CD73`
    dunkel, direkt aus dem Icon-Gold) als EINZIGE Akzentfarbe - Text
    auf Gold-Flächen ist in beiden Modi bewusst dunkle Tinte
    (`#1B140A`) statt Weiß, das hält den Foil-Look bei gefüllten
    Buttons. `ColorScheme.tertiary` trägt ein gedämpftes Grün
    (Sieg/Erfolg), bewusst getrennt vom Gold-Akzent. Technisch: je
    Modus `ColorScheme.fromSeed(...).copyWith(...)` statt eines
    komplett von Hand befüllten `ColorScheme` - robuster ohne echten
    Analyzer-Zugriff, da `fromSeed` immer ein vollständiges, gültiges
    Schema liefert und `copyWith` nur die entworfenen Rollen
    überschreibt.
  - **Typografie** (`google_fonts`, neue Abhängigkeit `^6.2.1`):
    Cinzel (geprägte Display-Schrift, an den "TAP"-Schriftzug
    angelehnt) für Display-/Headline-Rollen sowie `titleLarge` - davon
    erbt die Standard-App-Bar-Titelzeile automatisch, ohne dass jeder
    Screen einzeln angefasst werden musste. Manrope für den Rest
    (Fließtext, Listen-Titel, Buttons, Labels). Zusätzlich
    `AppTheme.statNumberStyle` (IBM Plex Mono, tabellarische Ziffern)
    für Kennzahlen wie Elo-Score/Lebenspunkte/Siegquote - bewusst NICHT
    rückwirkend in bestehende Screens (StatsScreen, LiveGameScreen)
    eingebaut, das ist Teil der vom Nutzer ans Ende verschobenen
    "Optischen Aufbereitung der Statistik-Anzeige" (siehe "Noch zu
    bauen") und nur als fertige Bausteine für diesen späteren Schritt
    hinterlegt.
  - `main.dart`: `MaterialApp` nutzte zunächst `theme: AppTheme.light`,
    `darkTheme: AppTheme.dark`, `themeMode: ThemeMode.system` (die App
    folgte der Geräte-Einstellung) - auf Nutzerwunsch aber direkt
    danach wieder auf **ausschließlich Dunkel** umgestellt (`theme:
    AppTheme.dark`, `themeMode: ThemeMode.dark`, unabhängig von der
    Geräte-Einstellung): der helle Modus wirkte im direkten Vergleich
    "übertrieben hell". `AppTheme.light` bleibt im Code erhalten (nur
    aktuell unbenutzt), falls später doch ein Hell-Modus gewünscht
    wird.
  - Eine bereits vorhandene Ad-hoc-Farbe wurde direkt an den neuen
    Akzent angeschlossen: die Pokal-Hervorhebung des Siegers auf
    `GameDetailScreen` nutzt jetzt `colorScheme.primary` statt eines
    hartkodierten `Colors.amber[700]`. Andere Status-Farben
    (`games_overview_screen.dart`: orange/grün für laufende/
    abgeschlossene Partien) blieben bewusst unangetastet - das ist
    kein Marken-Akzent, sondern ein allgemeiner Status-Indikator, und
    eine Umstellung wäre bereits "Optische Aufbereitung".

- **App-Icon vom mtg_stats_tracker-Vorgänger übernommen (auf
  Nutzerwunsch, Punkt 1 der "Noch zu bauen"-Liste angestoßen):** statt
  eines neuen Icons wollte der Nutzer explizit das bereits bestehende
  Icon der Vorgänger-App weiterverwenden. Da `mtg_stats_tracker` im
  selben verbundenen Ordner liegt, wurden die dort bereits fertig
  generierten Ausgabedateien direkt kopiert statt neu zu generieren
  (in dieser Umgebung steht kein Flutter-Tooling zur Verfügung):
  - **Android Launcher-Icon:** `mipmap-{m,h,x,xx,xxx}hdpi/
    ic_launcher.png` (Legacy) sowie das Adaptive Icon
    (`mipmap-anydpi-v26/ic_launcher.xml` + `drawable-{m,h,x,xx,xxx}hdpi/
    ic_launcher_foreground.png` + `ic_launcher_background` in
    `values/colors.xml`, Hintergrund `#000000`).
  - **iOS Launcher-Icon:** alle 15 PNGs in
    `Assets.xcassets/AppIcon.appiconset/` (Contents.json war bei
    beiden Projekten identisch, daher unverändert übernommen).
  - **Android-Splash-Screen** (auf Nachfrage zusätzlich gewünscht,
    damit Icon und Splash zusammenpassen): ebenfalls 1:1 von
    `mtg_stats_tracker` übernommen - `drawable(-v21)/background.png`
    + `launch_background.xml`, `drawable-{m,h,x,xx,xxx}hdpi/splash.png`
    (helles Theme) und `android12splash.png` (+ `drawable-night-*`-
    Varianten fürs Dunkelmodus-Pendant der Android-12-Splash-API),
    `values(-night)(-v31)/styles.xml`. iOS bewusst AUSGENOMMEN - das
    war schon im Vorgängerprojekt so konfiguriert
    (`flutter_native_splash: ios: false`), dort blieb der
    Flutter-Standard-Splash. Zusätzlich `assets/icon/tap_icon_fg.png`
    (Quellbild) übernommen und die `flutter_native_splash`-
    Konfiguration (`^2.4.7`, `dev_dependencies`) 1:1 in die pubspec.yaml
    übertragen - rein informativ/für den Fall, dass der Generator
    (`dart run flutter_native_splash:create`) später erneut laufen
    soll (z. B. nach einem Icon-Wechsel); die eingecheckten
    Ausgabedateien sind bereits vollständig und funktionieren auch
    ohne erneuten Lauf.

  Das eigentliche App-Theme (Farben/Look der App selbst) war davon
  zunächst unberührt - siehe den eigenen Fixes-Eintrag "App-Theme
  'Vault & Foil'" weiter unten für die spätere Umsetzung.

  **Nachtrag, nachdem "Vault & Foil" feststand:** die Splash-
  Hintergrundfarbe (bis dahin `#000000`, 1:1 vom Vorgänger übernommen)
  wurde auf das Theme-Petrol `#0B1E26` ("Vault") umgestellt, damit
  Icon, Splash und App-Hintergrund nahtlos ineinander übergehen -
  konkret die 1x1-Pixel-Hintergrundbilder `drawable(-v21)/
  background.png` (Splash vor Android 12) sowie
  `android:windowSplashScreenBackground` in `values(-night)-v31/
  styles.xml` (Splash ab Android 12) und die `flutter_native_splash`-
  Konfiguration in der pubspec.yaml (nur informativ, siehe oben). Der
  `ic_launcher_background` in `values/colors.xml` (Hintergrund des
  Adaptive Icons selbst) blieb bewusst `#000000` - das ist Teil des
  Icon-Designs, nicht der Splash-Hintergrund, und war nicht gemeint.

- **Datei-Export: kein Ordner wählbar (Nutzer-Frage, ob das am
  Emulator liegt):** Der Datei-Export nutzte bis dahin ausschließlich
  das System-"Teilen"-Sheet (`share_plus`) - darüber lässt sich nur
  eine Ziel-App auswählen (Mail, Messenger, Dateien-App etc.), keine
  direkte Ordnerauswahl. Das lag nicht am Emulator (der aber, mangels
  installierter Apps wie Google Drive, weniger Freigabeziele als ein
  echtes Telefon anbietet und den Eindruck dadurch verstärkt hat) -
  ist Design des Share-Sheets an sich. Fix: zusätzlicher Button "In
  Ordner speichern" in `ExportWizardScreen`, der stattdessen
  `FilePicker.platform.saveFile` nutzt (nativer
  Speichern-unter-Dialog, auf Android/iOS über das Storage Access
  Framework - liefert dort direkt den geschriebenen Pfad zurück, auf
  Desktop-Plattformen nur den gewählten Pfad, weshalb zusätzlich ein
  `exists()`-Fallback die Datei dort selbst schreibt). Der
  ursprüngliche Teilen-Button (`_shareAsFile`, vormals `_export`)
  bleibt bestehen; beide Wege teilen sich jetzt `_buildExportJson`
  für den eigentlichen Bundle-Aufbau. Keine neuen Android/iOS-
  Berechtigungen nötig, da SAF-Dialoge ohne `WRITE_EXTERNAL_STORAGE`
  auskommen.

- **`.catchError` auf nicht-void `Future<T>` (Analyzer-Fehler
  `body_might_complete_normally_catch_error`), auf Nutzeranfrage
  behoben (Meldung zu `group_detail_screen.dart` Zeile 191, "This
  'onError' handler must return a value assignable to 'int', but
  ends without returning a value"):** `Future<T>.catchError(...)`
  verlangt vom Analyzer, dass der `onError`-Callback `FutureOr<T>`
  zurückgibt. Bei `T == void` ist ein Callback ohne `return`
  automatisch gültig, bei nicht-`void` `T` (z. B. `Future<int>` wie
  bei `createPlayer`/`addMember`/`createDeck`/`createGroup`/
  `createGroupWithMember`) nicht - der Analyzer meldet dann diesen
  Fehler. Auch `.then((x) => someFutureInt).catchError(...)`-Ketten
  sind betroffen, da `.then()` mit einem Future-zurückgebenden
  Callback auf dessen Typ abflacht.

  Da dieselbe Baustelle im ganzen Repo vorkam (`grep -rn catchError
  lib/` fand 8 Treffer in 6 Dateien), wurde einheitlich bereinigt -
  nicht nur die genannte Fundstelle, sondern auch bereits
  "unkaputte" `.catchError`-Stellen auf `Future<void>` (aus
  Konsistenzgründen):
  - `group_detail_screen.dart`: `PopupMenuButton.onSelected`
    (rename/archive) sowie `_AddMemberDialogState._addExisting` und
    `_createAndAdd` auf `async`/`await`/`try-catch` umgestellt.
  - `deck_form_dialog.dart`: `_save()` auf `Future<void> ... async`
    umgestellt; die alte `existingDeck == null ? createDeck(...) :
    updateDeck(...)`-Ternary (mit uneindeutigem `Future<int>`/
    `Future<void>`-LUB) wurde durch ein explizites `if/else` mit
    `await` in einem `try/catch`-Block ersetzt. Der
    Archivieren-Button wurde ebenso umgestellt.
  - `groups_overview_screen.dart`: `_CreateGroupDialogState._create()`
    (die zweite tatsächlich kaputte Stelle neben der gemeldeten) auf
    dasselbe Muster umgestellt.
  - `player_detail_screen.dart`: der `renamePlayer`-Aufruf im
    Umbenennen-`onSave` (war technisch nicht kaputt, da
    `Future<void>`, aber aus Konsistenzgründen mit umgestellt).
  - Der erklärende Kommentar in `rename_dialog.dart`, der zuvor
    `catchError` als Beispiel nannte, wurde entsprechend angepasst.

  **Regel für künftigen Code in diesem Projekt:** niemals
  `.catchError(...)`-Ketten verwenden, auch nicht bei `Future<void>`.
  Stattdessen immer die aufrufende Methode als `async` deklarieren
  und mit `try { await ...; } catch (e) { messenger.showSnackBar(...);
  }` arbeiten - das ist unabhängig vom Rückgabetyp der aufgerufenen
  Repository-Methode sicher und funktioniert auch als
  `VoidCallback`/`onPressed`/`onSelected`/`onSave`-Tear-off oder
  -Literal (Darts Void-Context-Subtyping erlaubt `Future<void>
  Function(...)` überall dort, wo `void Function(...)` erwartet
  wird).

- **Partien-QR-Teilen + "on the fly"-Teilnehmer-Zuordnung beim Import
  (auf Nutzeranfrage, Nachtrag zum Export/Import-Eintrag unten):** Der
  Nutzer wollte zusätzlich einzelne Partien per QR teilen können und
  fragte konkret danach, wie ein Import so strukturiert sein muss,
  dass er beim Import sagen kann "das bin ich, ich habe statt WU genau
  dieses (WU) Deck gespielt" - also ein Teilnehmer beim Import manuell
  einem eigenen bekannten Spieler samt eigenem Deck zugeordnet werden
  kann, unabhängig vom automatischen Namens-Abgleich.

  Umsetzung:
  - `GameDetailScreen` bekam ein App-Bar-Icon "Partie teilen (QR)"
    (nur bei abgeschlossenen Partien) ->
    `ExportService.buildGameQrBundle`: Bundle mit genau der einen
    Partie plus `PlayerExport`-Einträgen für jeden bekannten
    Teilnehmer (damit sie beim Import optional als neue Spieler
    angelegt werden können) - bewusst OHNE vollständige
    `DeckExport`-Einträge, um den QR-Code klein zu halten (dafür siehe
    nächster Punkt).
  - `GameParticipantExport` bekam ein neues Feld `colorIdentity`, das
    IMMER gesetzt wird (bei bekannten Teilnehmern von deren Deck
    übernommen, bei anonymen von `anonymousColorIdentity`) - dadurch
    ist die Farbidentität jedes Teilnehmers auch dann bekannt, wenn
    das zugehörige Deck selbst nicht mit im Bundle ist (z. B. beim
    schlanken Partien-QR-Bundle).
  - QR-Payload-Obergrenze in `qr_share_dialog.dart` von 1500 auf 2500
    Bytes angehoben - eine Partie mit mehreren Teilnehmern (inkl.
    Notizen) braucht spürbar mehr Platz als ein einzelnes Deck/
    Spielerprofil, passt aber weiterhin deutlich in die
    QR-Kapazitätsgrenze.
  - Neuer Import-Baustein `ParticipantOverride`
    (`lib/features/import/model/participant_override.dart`, drei
    Modi: `auto`/`assign`/`anonymous`) + `GameImportTile`
    (`lib/features/import/view/widgets/`): jede Partie in der
    Import-Vorschau ist jetzt aufklappbar (Chevron-Icon neben der
    Checkbox) und zeigt pro Teilnehmer ein Dropdown "Zuordnung"
    ("Automatisch" / "Ich (Name)" / jeder andere bereits bekannte
    lokale Spieler / "Anonym bleiben"). Bei Zuordnung zu einem
    konkreten Spieler erscheint darunter ein zweites Dropdown mit
    dessen EIGENEN Decks (`playerDecksProvider`) - gibt es genau ein
    eigenes Deck mit exakt passender Farbidentität, wird es einmalig
    als Empfehlung vorausgewählt (danach frei änderbar), das ist der
    vom Nutzer angefragte "statt WU genau dieses (WU) Deck"-Fall.
    `ImportService.performImport` respektiert eine gesetzte
    Übersteuerung für den jeweiligen Teilnehmer mit Vorrang vor dem
    automatischen Namens-Abgleich (`assign` -> direkt die gewählte
    Spieler-/Deck-id, `anonymous` -> erzwungen anonym trotz
    ggf. auflösbarem Namen, kein Override/`auto` -> unverändertes
    Verhalten wie zuvor). `ImportSelection` trägt die Übersteuerungen
    dafür jetzt zusätzlich in `participantOverrides` (Partie-Index ->
    Teilnehmer-Index -> `ParticipantOverride`).
  - Der bisherige Anonym-Fallback beim automatischen Namens-Abgleich
    (nicht auflösbarer `playerName`) nutzt jetzt ebenfalls direkt
    `colorIdentity` statt der vorherigen, fragileren Suche in
    `bundle.decks` nach einem passenden `DeckExport`.

- **Export/Import implementiert (Datei + QR, auf Nutzeranfrage "Gehe
  nun zum nächsten offenen Punkt" - Punkt 1 der "Noch zu bauen"-Liste):**
  Vor der Umsetzung drei Design-Fragen mit dem Nutzer geklärt (siehe
  Standard-Regel "bei Unklarheiten nachfragen"):
  1. **Gruppen im Bundle:** Ja, Gruppen (inkl. Mitgliederliste) sind
     Teil des Export/Import-Bundles (gewählt) - damit lässt sich eine
     komplette Spielgruppen-Konfiguration an einen Mitspieler
     übertragen oder sichern. War bereits seit dem ursprünglichen
     Export/Import-Abschnitt als offene Frage vermerkt.
  2. **Duplikat-Prüfung beim Import:** Automatischer Namens-Abgleich
     (gewählt) statt komplett manueller Auswahl. Da es KEINE
     geräteübergreifenden IDs gibt (nur lokale Drift-Autoincrement-
     IDs), werden Spieler per Name und Decks per (Besitzer-Name +
     Deck-Name) case-insensitive gegen den aktuellen Datenbestand
     abgeglichen; Treffer gelten als "vermutlich schon vorhanden" und
     sind in der Vorschau standardmäßig ABGEWÄHLT (der Nutzer kann
     trotzdem zustimmen). Partien werden NIE automatisch abgeglichen
     (zu fehleranfällig ohne stabile IDs), sondern immer einzeln mit
     Datum/Modus/Teilnehmern angezeigt - dort aber standardmäßig
     AUSGEWÄHLT, da Duplikate hier die Ausnahme sind, die der Nutzer
     anhand der sichtbaren Details leicht selbst erkennt.
  3. **QR-Umfang:** Ein einzelnes Deck ODER ein einzelnes
     Spielerprofil OHNE dessen Decks (gewählt), nicht automatisch
     alle Decks eines Spielers mit - zwei getrennte, einfache
     Aktionen auf `PlayerDetailScreen` ("Deck teilen" pro Deck-Zeile,
     "Spieler teilen" im App-Bar-Menü), beide garantiert klein genug
     für einen einzelnen QR-Code.

  **Zentrale technische Entscheidung:** `ExportBundle` referenziert
  alle Verknüpfungen (Deck->Besitzer, Gruppe->Mitglieder, Partie->
  Teilnehmer/Deck/Gruppe) per NAME statt per lokaler Drift-id, da
  Autoincrement-IDs nur innerhalb der eigenen Datenbank gültig sind.
  `ImportService.performImport` baut daraus Name->id-Zuordnungen, die
  zunächst mit dem vorhandenen Datenbestand vorbelegt und dann von
  tatsächlich neu importierten Einträgen überschrieben werden
  ("frischester Treffer gewinnt": ausgewählte Bundle-Einträge binden
  nachfolgende Referenzen innerhalb desselben Bundles an sich selbst,
  ein abgewähltes Duplikat fällt auf den bereits vorhandenen Eintrag
  zurück). Praktischer Nebeneffekt: Beim Wiederherstellen der eigenen
  Daten auf einem neuen Gerät (Setup-Wizard legt zuerst den neuen
  Self-Player an, danach Import der alten Datei) greift der
  Namens-Abgleich von selbst, sofern derselbe Name verwendet wird -
  die eigenen Decks/Partien landen dann korrekt beim neuen
  Self-Player statt bei einem doppelten Eintrag. isSelf wird beim
  Import grundsätzlich NIE gesetzt (jedes Gerät hat bereits genau
  einen Self-Player, siehe Players-Tabelle) - ein importierter Spieler
  wird immer als normaler bekannter Spieler angelegt.

  Weitere Details:
  - Ein Teilnehmer, dessen `playerName` beim Import nicht auflösbar
    ist (Spieler weder importiert noch bereits vorhanden), wird NICHT
    stillschweigend fallengelassen, sondern als anonymer Teilnehmer
    übernommen (`anonymousLabel` = ursprünglicher Name), mit Hinweis
    in `ImportResult.warnings`. Gleiches Prinzip für ein Deck ohne
    auflösbaren Besitzer (wird übersprungen, ebenfalls mit Hinweis) -
    ein Import bricht dadurch nie komplett ab, sondern kommt so
    vollständig wie möglich an.
  - `Games.firstBloodParticipantId` wird als bundle-lokaler Index in
    die `participants`-Liste exportiert/importiert (`
    firstBloodParticipantIndex`), da die echte id erst nach dem
    Import der Teilnehmer bekannt ist.
  - Nur ABGESCHLOSSENE Partien werden exportiert (eine laufende
    Live-Partie auf einem anderen Gerät zu teilen ergäbe keinen Sinn).
  - `isWinner` und `placement` werden beide unverändert aus der
    Quelldatenbank übernommen (nicht aus placement abgeleitet), damit
    auch Team-Modi (2HG/Erzfeind) verlustfrei übertragen werden.
  - QR-Payload-Obergrenze defensiv bei 1500 Bytes gezogen
    (`qr_share_dialog.dart`) - für ein einzelnes Deck/Spielerprofil in
    der Praxis nie relevant, zeigt bei Überschreitung einen Hinweis
    auf den Datei-Export statt einen möglicherweise unlesbaren
    QR-Code zu erzeugen.
  - Kamera-Berechtigung für `mobile_scanner` ergänzt:
    `android.permission.CAMERA` in AndroidManifest.xml,
    `NSCameraUsageDescription` in ios/Runner/Info.plist.
  - Das `archive`-Paket (in pubspec.yaml bereits vorbereitet) wird
    bewusst NICHT verwendet - eine JSON-Datei für einen persönlichen
    MTG-Tracker ist klein genug, Kompression wäre unnötige
    Komplexität. Package-Deklaration unverändert gelassen.
  - **Bekannte Lücke:** Import ist erst NACH dem Setup-Wizard nutzbar
    (Home-Screen setzt einen bestehenden Self-Player voraus). Eine
    Wiederherstellung "vor" dem allerersten Einrichten ist also nicht
    möglich - der Nutzer muss den Setup-Wizard einmal durchlaufen
    (eigenen Namen vergeben) und kann direkt danach importieren (siehe
    Namens-Abgleich-Mechanik oben). War kein Teil der abgestimmten
    Design-Fragen, wird hier als bewusste, pragmatische
    Scope-Entscheidung dokumentiert statt stillschweigend offen zu
    lassen.
  - **Unsicherheit, bitte beim ersten Testlauf gegenprüfen:**
    `ExportWizardScreen._export` nutzt `SharePlus.instance.share(
    ShareParams(...))` (share_plus v12-API) - da kein Zugriff auf die
    tatsächliche Paket-Dokumentation bestand, ist dieser einzelne
    Aufruf ein Best-Effort und sollte vom Compiler/Analyzer bestätigt
    werden.

  Neue Dateien: `lib/features/export/model/export_bundle.dart` (neu
  geschrieben, ersetzt den alten Platzhalter), `export_selection.dart`
  (um `includeGroups` erweitert), `lib/features/export/controller/
  export_service.dart` + `provider/export_service_provider.dart`,
  `lib/features/export/view/screen/export_wizard_screen.dart`,
  `lib/features/export/view/widgets/qr_share_dialog.dart`,
  `lib/features/import/model/import_selection.dart` (um Gruppen
  erweitert), `import_preview.dart` (neu), `lib/features/import/
  controller/import_service.dart` + `provider/
  import_service_provider.dart`, `lib/features/import/view/screen/
  import_wizard_screen.dart` + `qr_scan_screen.dart`. Home-Screen:
  zwei neue Buttons "Daten exportieren"/"Daten importieren".
  PlayerDetailScreen: "Teilen (QR)" pro Deck + für den Spieler selbst.

- **dart_json_mapper entfernt** (ursprünglich aus mtg_stats übernommen,
  aber im Code nie tatsächlich verwendet): Es verursachte einen
  Versionskonflikt mit `drift_dev`/`intl` beim `flutter pub get`
  (dart_json_mapper zieht alte `build`/`intl`-Ranges, die mit dem
  aktuellen `drift_dev` kollidieren). JSON-(De-)Serialisierung für
  Export/Import läuft stattdessen über `dart:convert` +
  die von Drift automatisch generierten `toJson()`/`fromJson()`-
  Methoden auf den Tabellen-Datenklassen - dafür ist kein Zusatzpaket
  nötig.

- **`competitiveCommander` zu `GameMode` hinzugefügt:** Enum-Werte
  ändern das generierte Drift-Schema (`app_database.g.dart`). Nach dem
  Pull dieser Änderung einmalig ausführen, bevor die App gebaut wird:
  `dart run build_runner build --delete-conflicting-outputs`
  (aus dieser Cloud-Umgebung heraus nicht möglich, da hier kein Dart/
  Flutter-Tooling zur Verfügung steht).

- **Erneuter Schema-Wechsel (Partner-Commander/Deck-Felder,
  Startposition, Unentschieden):** `Decks` (secondCommanderName,
  buildType, bracket, isProxy, isTournamentLegal, deckLink),
  `GameParticipants` (startPosition) und `Games` (isDraw) wurden um
  neue Spalten erweitert. Auch hierfür vor dem nächsten Build erneut
  `dart run build_runner build --delete-conflicting-outputs` ausführen
  (derselbe manuelle Schritt wie oben - kann bei mehreren aufeinander
  folgenden Schema-Änderungen einmalig gesammelt am Ende ausgeführt
  werden, muss aber vor dem nächsten `flutter run` passiert sein).

- **`use_build_context_synchronously`-Warnung behoben:** Der Dart-
  Analyzer erkennt `if (context.mounted) NavigatorAufruf();` als
  einzeiliges Statement (ohne Block) nicht zuverlässig als gültige
  Absicherung eines `BuildContext`-Zugriffs nach einem `await`. Fix
  (in allen betroffenen Stellen, u. a. `GameSetupScreen`,
  `DeckFormDialog`, den Gruppen-/Spieler-Detailscreens):
  Guard-Klausel mit frühem Return statt Inline-If, also
  `if (!context.mounted) return; Navigator.of(context).pop();` statt
  `if (context.mounted) Navigator.of(context).pop();`. Für künftigen
  Code in diesem Projekt: immer die Guard-Klauseln-Variante verwenden,
  nicht die einzeilige Inline-Variante.

- **`_dependents.isEmpty`-Assertion beim Umbenennen behoben - erste
  zwei Versuche (Teil 1+2, beide unzureichend, hier nur zur
  Nachvollziehbarkeit dokumentiert):** Zunächst vermutet: Kollision
  zwischen PopupMenu-Schließ-Animation und sofortigem
  `showDialog(...)` (Fix: künstliche Verzögerung). Dann vermutet: die
  `Speichern`-Buttons riefen erst `await repo.rename(...)` und danach
  `Navigator.pop()` auf, wodurch ein durch den Schreibvorgang
  ausgelöster Live-Rebuild des darunterliegenden `StreamProvider`
  (z. B. `playerByIdProvider`) mit dem Pop kollidierte (Fix:
  Reihenfolge umgedreht, erst poppen, dann schreiben). Beide Fixes
  waren zumindest unvollständig - der Fehler trat laut Nutzer-Report
  weiterhin auf, **auch beim Abbrechen** (kein Schreibvorgang
  beteiligt), was beide Theorien widerlegte.

- **`_dependents.isEmpty`-Assertion beim Umbenennen behoben (Teil 3 -
  tatsächliche, per Stacktrace bestätigte Ursache):** Der Nutzer
  konnte einen vollständigen Stacktrace liefern. Primärer Fehler:
  `"A TextEditingController was used after being disposed"`, geworfen
  beim Rebuild eines noch sichtbaren `TextField` - erst DANACH
  kaskadierte daraus die `_dependents.isEmpty`-Assertion sowie
  `"Tried to build dirty widget in the wrong build scope"`. Ursache:
  `_showRenameDialog` (und baugleich `_showCreateGroupDialog`,
  `_showAddMemberDialog`) erzeugten den `TextEditingController` als
  lokale Variable, riefen `await showDialog(...)` auf und disposten
  den Controller direkt danach. `Navigator.pop()` entfernt die Route
  zwar sofort aus der History (wodurch die `showDialog`-Future
  zurückkehrt), das `AlertDialog`-Widget (inkl. `TextField`) bleibt
  aber für die Dauer seiner Exit-Animation noch im Baum - wird der
  Controller in diesem Fenster disposed, wirft ein Rebuild des noch
  animierenden `TextField` die Exception. Das erklärt auch, warum der
  Fehler unabhängig von Speichern/Abbrechen auftrat: beide Buttons
  poppen die Route, nur DANACH lief in beiden Fällen dasselbe
  problematische `controller.dispose()`.

  Fix: alle betroffenen Dialoge auf ein eigenes StatefulWidget
  umgestellt, das seinen `TextEditingController` in `initState()`
  erzeugt und in `dispose()` freigibt - Flutter ruft `dispose()`
  garantiert erst auf, nachdem das Widget vollständig aus dem Baum
  entfernt wurde, also nach Abschluss der Exit-Animation. Neuer
  gemeinsamer Baustein `lib/core/widgets/rename_dialog.dart`
  (`showRenameDialog(...)`) für Spieler- und Gruppen-Umbenennen;
  `GroupDetailScreen`s `_AddMemberDialog` und
  `GroupsOverviewScreen`s `_CreateGroupDialog` wurden ebenso zu
  eigenen `ConsumerStatefulWidget`s. **Für künftigen Code in diesem
  Projekt: einen `TextEditingController`, der in einem `showDialog`-
  Inhalt verwendet wird, NIE als lokale Variable einer Funktion
  anlegen und nach `await showDialog(...)` manuell disposen -
  IMMER ein eigenes StatefulWidget mit `initState`/`dispose` dafür
  verwenden.** (Die vorherige Vermutung zu Part 1/2 oben war
  dementsprechend nicht der eigentliche Auslöser, wird hier aber der
  Nachvollziehbarkeit halber nicht gelöscht.)

- **"Mitglied hinzufügen"-Button reagierte nicht behoben:**
  `GroupDetailScreen._showAddMemberDialog` fragte VOR dem Öffnen des
  Dialogs zwei Provider einmalig per
  `await ref.read(xyzProvider.future)` ab und übergab die Ergebnisse
  als statische Liste in den Dialog - wurde diese Funktion als
  Fire-and-forget aus `onPressed` heraus aufgerufen (ohne `await`),
  wäre ein Fehler in einem dieser beiden Awaits als unbehandelter
  Future-Fehler nur in der Konsole gelandet, ohne dass der Dialog je
  erscheint oder ein Hinweis in der UI zu sehen ist - exakt das vom
  Nutzer beschriebene Symptom ("Tap tut nichts"). Fix: im Zuge der
  Umstellung auf `_AddMemberDialog` (siehe oben) werden die Provider
  jetzt reaktiv per `ref.watch(...)` INNERHALB des Dialogs gelesen
  (mit Ladeanzeige, während sie auflösen) statt vorab einmalig
  abgefragt - kein Vor-Await mehr, das lautlos scheitern könnte.

- **Fehlende Längenvalidierung bei Namensfeldern behoben:** Namen
  (Spieler, Gruppe, Deck) hatten zwar ein DB-seitiges Längenlimit
  (`withLength(min: 1, max: ...)` in den jeweiligen Tabellen), aber
  keine UI-Beschränkung/Fehlermeldung. Ein zu langer Name wurde beim
  Speichern durch eine CHECK-Constraint-Verletzung abgelehnt, ohne
  dass die UI das anzeigte - im Setup-Wizard blieb der Ladeindikator
  dadurch dauerhaft aktiv, ohne dass der Self-Player angelegt wurde.
  Fix: allen betroffenen `TextField`s ein zur jeweiligen Tabellen-
  spalte passendes `maxLength` gegeben (Spieler-/Gruppenname: 60,
  Deckname: 80) - Flutter verhindert damit die Eingabe zu langer Werte
  direkt und zeigt einen Zähler an. Zusätzlich fängt
  `SetupFlowController.finishSetup()` jetzt Fehler nicht mehr
  unbehandelt ab, sondern setzt `isSaving` in einem `finally`-Block
  immer zurück; `SetupWizard` zeigt einen verbleibenden Fehler als
  SnackBar an.

- **"Gruppe umbenennen" reagierte nicht (eigener Fehler beim Teil-3-
  Fix oben eingebaut):** Beim Umstieg auf `showRenameDialog` wurde in
  `GroupDetailScreen` der aktuelle Gruppenname per
  `await ref.read(groupByIdProvider(groupId).future)` VOR dem Öffnen
  des Dialogs abgefragt - exakt dieselbe Fehlerklasse wie zuvor beim
  kaputten "Mitglied hinzufügen"-Button (ein await vor dem Öffnen
  eines fire-and-forget aufgerufenen Dialogs, der bei einem Problem
  lautlos scheitert, ohne dass je etwas erscheint). Fix: `groupAsync`
  wird jetzt wie `membersAsync` reaktiv per `ref.watch(...)` in
  `build()` gelesen, der aktuelle Gruppenname ist beim Antippen von
  "Umbenennen" dadurch bereits synchron vorhanden - kein await mehr
  nötig. **Für künftigen Code in diesem Projekt: einen Dialog niemals
  hinter einem `await ref.read(provider.future)` öffnen, wenn der
  Wert stattdessen auch per `ref.watch(...)` reaktiv im umgebenden
  `build()` verfügbar gemacht werden kann.**

- **Platzierungs-Vorschlag am Ende der Live-Erfassung (neue
  Funktion):** `LiveGameScreen` merkt sich pro Teilnehmer, wann dessen
  Lebenspunkte zum ersten Mal auf `<= 0` fallen (`_eliminationOrder`,
  chronologisch, nur der erste Unterschreitungs-Zeitpunkt zählt - auch
  wenn die Lebenspunkte danach wieder steigen und erneut fallen). Beim
  Öffnen des Platzierungs-Dialogs (`_ResultDialog`, via "Partie
  beenden") wird daraus ein Vorschlag berechnet
  (`_suggestedPlacements()`): wer zuerst auf `<= 0` fiel, bekommt den
  letzten Platz, wer als zweites fiel den vorletzten usw. Teilnehmer,
  die nie auf `<= 0` fielen ("Überlebende"), bekommen Platz 1, wenn es
  genau einen solchen gibt; gibt es mehrere gleichzeitige Überlebende
  bei Spielende, bleibt deren Platzierung bewusst frei (`null`), da die
  Reihenfolge unter ihnen nicht ermittelbar ist - der bestehende
  `game_setup_validator` verlangt ohnehin eine lückenlose Platzierung
  für alle Teilnehmer, sodass der "Bestätigen"-Button in diesem Fall
  automatisch deaktiviert bleibt, bis die verbleibenden Plätze manuell
  gesetzt werden. Der Vorschlag ist nur eine Vorbelegung der
  Stepper-Werte in `_ResultDialog` (`initialPlacements`) - alle Werte
  bleiben wie zuvor frei editierbar, ein Hinweistext macht das im
  Dialog kenntlich. Gilt nur für den individuellen
  Platzierungs-Modus (Commander/cEDH); bei Team-Modi (Archenemy/2HG)
  wird die Platzierung weiterhin ausschließlich über die
  Sieger-Auswahl gesetzt, der Vorschlag wird dort ignoriert. Schwellenwert
  `<= 0` wurde vom Nutzer explizit bestätigt (initial gab es im
  Auftrag einen Widerspruch zwischen "<= 0" und "maximal 5").

- **Deck nachträglich änderbar für bereits hinzugefügte bekannte
  Teilnehmer (neue Funktion):** Bisher ließ sich das Deck eines
  Teilnehmers nur bei dessen Hinzufügen über
  `AddKnownParticipantDialog` festlegen - insbesondere der automatisch
  vorbelegte Ich-Spieler (`_addSelfIfNeeded` in `GameSetupScreen`)
  bekam nie ein Deck zugewiesen und musste dafür erst entfernt und
  über den Bekannte-Spieler-Dialog neu hinzugefügt werden. Neuer
  Baustein `lib/features/games/view/widgets/select_deck_dialog.dart`
  (`showSelectDeckDialog`, Rückgabetyp `DeckSelection` mit `deckId ==
  null` für die bewusste Wahl "Kein Deck angeben" - unterscheidbar vom
  Abbruch, der `null` statt eines `DeckSelection`-Objekts liefert)
  kapselt die reine Deck-Auswahl-Liste eines bekannten Spielers
  eigenständig (nicht wiederverwendet in
  `add_known_participant_dialog.dart`, da dessen zweistufiger Dialog
  mit "Zurück"-Navigation zur Spielerauswahl eine andere Struktur
  braucht). `_ParticipantCard` in `GameSetupScreen` zeigt nun bei jedem
  bekannten Teilnehmer (`!draft.isAnonymous`) einen kleinen
  Stift/Deck-Icon-Button neben dem Deck-Namen, der
  `GameSetupScreenState._changeDeck(index)` auslöst. Dafür bekam
  `GameParticipantDraft` eine neue Methode `withDeck(...)` (bewusst
  getrennt von `copyWith`, da dort ein `deckId: null` nicht von "nicht
  ändern" unterscheidbar wäre).

- **Statistik-Dashboard - mit dem Nutzer abgestimmter Umfang der
  ersten Version:** Auf Nachfrage (siehe Standard-Regel "bei
  Unklarheiten nachfragen") drei Design-Entscheidungen geklärt, bevor
  gebaut wurde: (1) Filterung global MIT Umschalter auf eine bestimmte
  Gruppe (nicht nur global, nicht nur pro Gruppe) - `_selectedGroupId`
  in `StatsScreen`, `null` = "Alle Partien"; (2) Kennzahlen der ersten
  Version bewusst nur Siegquote gesamt + pro Deck (nicht: Streaks,
  First-Blood-Quote, Partienanzahl/Ø-Dauer - diese bleiben als
  spätere Ausbaustufe in "Noch zu bauen" oben vorgemerkt); (3)
  Perspektive nur die eigene Statistik (Ich-Spieler), kein Vergleich
  zwischen mehreren Spielern einer Gruppe. "Sieg" folgt dabei
  derselben Definition wie überall sonst in der App
  (`GameParticipant.isWinner`, aus `placement == 1` abgeleitet) - bei
  einem Unentschieden zählt das also für ALLE Teilnehmer als Sieg, wird
  in der Statistik nicht separat ausgewiesen.

- **Compile-Fehler nach Statistik-Dashboard behoben (`equals` vs.
  `equalsValue` bei Drift-Enum-Spalten):** `GamesRepository.
  watchSelfGameStats` filterte mit
  `db.games.status.equals(GameStatus.completed)` - Fehler in der IDE:
  "The argument type 'GameStatus' can't be assigned to the parameter
  type 'String'". Ursache: Bei Tabellenspalten mit Enum-Konverter
  (`textEnum<T>()`, z. B. `Games.status`/`Games.mode`/`Games.
  entryMode`, `Decks.buildType`) ist die geerbte `.equals(...)`-Methode
  für den zugrunde liegenden SQL-Spaltentyp (`String`) typisiert, nicht
  für den Dart-Enum-Wert. Fix: `.equalsValue(GameStatus.completed)`
  verwendet - diese von Drift für `GeneratedColumnWithTypeConverter`
  bereitgestellte Methode nimmt den Dart-Enum-Wert entgegen und
  wandelt ihn intern über den Converter in den SQL-Typ um. **Für
  künftigen Code in diesem Projekt: bei einem Vergleich gegen eine
  `textEnum<T>()`-Spalte in einer manuellen `where`-Klausel (join-
  basierte Queries wie hier, nicht die generierte Manager-API) immer
  `.equalsValue(...)` statt `.equals(...)` verwenden.**

- **Statistik-Dashboard - Modus-Filter nachgetragen (auf
  Nachfrage):** Der Nutzer fragte nach dem ersten Ausliefern, ob die
  Statistik künftig auch nach Modus (EDH/cEDH/2HG/Erzfeind)
  differenzieren wird - bis dahin wurden alle Modi in der Siegquote
  zusammengezählt (nicht Teil der drei ursprünglich abgestimmten
  Design-Entscheidungen, siehe Eintrag oben). Auf Nachfrage bestätigt:
  ja, jetzt ergänzt. `SelfGameStatsRow` (GamesRepository.
  watchSelfGameStats) führt jetzt zusätzlich `mode: GameMode` mit;
  `StatsScreen` bekam ein zweites, IMMER sichtbares Dropdown "Modus"
  (`_selectedMode`, `null` = "Alle Modi", Labels über die bestehende
  `gameModeLabels`-Map) neben dem weiterhin nur bei
  `trackOtherPlayers == true` sichtbaren Gruppen-Dropdown - beide
  Filter sind unabhängig voneinander UND-verknüpft
  (`rows.where(...).where(...)`, siehe `_StatsBody.build`).

- **Statistik-Dashboard - Performance-Korrelationen + Elo-Score
  (auf Nutzeranfrage):** Der Nutzer wollte zusätzlich beantworten
  können, ob er tendenziell gewinnt, wenn er früh startet oder wenn
  eine Partie lange dauert, ob er bestimmte Farbkombinationen
  besonders gut spielt, sowie einen Elo-basierten Score (0-100). Da
  "Elo" mehrere valide, sehr unterschiedliche Umsetzungen zulässt,
  wurden vor der Umsetzung zwei Design-Fragen mit dem Nutzer geklärt:
  1. **Umfang:** Nur ein Score für den Ich-Spieler (gewählt) statt
     eines echten Multiplayer-Elo-Systems mit sich gegenseitig
     beeinflussenden Ratings für alle bekannten Spieler (hätte eine
     neue Rating-Historie-Tabelle gebraucht).
  2. **Berechnungsgrundlage je Partie:** Nach Platzierung (gewählt)
     statt nur Sieg/Niederlage.
  Umsetzung (`lib/features/stats/model/player_performance_stats.dart`,
  reine Funktionen ohne DB-Zugriff, analog zu `player_stats.dart`):
  - `computeEloScore`: Partien werden chronologisch durchlaufen,
    Rating startet bei 1500. Je Partie ein "tatsächliches Ergebnis" S
    in [0, 1]: bei Unentschieden 0.5; bei erfasster Einzelplatzierung
    (Commander/cEDH) `(participantCount - placement) /
    (participantCount - 1)` (1. Platz = 1.0, letzter Platz = 0.0);
    sonst (Team-Modi 2HG/Erzfeind ohne Einzelplatzierung, oder
    fehlende Daten) ersatzweise Sieg/Niederlage (1.0/0.0). Da KEINE
    Gegner-Ratings erfasst werden (siehe Umfang oben), gilt als
    Erwartungswert je Partie neutral 0.5; Rating-Änderung = K *
    (S - 0.5), K = 32. Das Endrating wird über die normale
    Elo-Erwartungsformel auf 0-100 abgebildet (1500 -> 50, +-400
    Rating -> ca. +-91/9) - entspricht der geschätzten
    Gewinnwahrscheinlichkeit gegen einen durchschnittlichen (1500er)
    Gegner. In der UI mit Hinweistext, dass der Wert ohne
    Gegner-Bewertungen eine Tendenz ist, keine exakte Kennzahl (bei
    < 10 Partien zusätzlicher Hinweis auf geringe Aussagekraft).
  - `computeWinRateByStartPosition`: normiert die Startposition auf
    `(startPosition - 1) / (participantCount - 1)` (0 = zuerst am
    Zug, 1 = zuletzt), damit unterschiedlich große Partien
    vergleichbar bleiben, und teilt in drei Terzile (Früh/Mittel/
    Spät). Partien ohne erfasste Startposition (z. B. manuell
    nachgetragen) werden ausgelassen.
  - `computeWinRateByDuration`: teilt die Partien mit erfasster Dauer
    (nur Live-Erfassung) in drei Terzile der eigenen Partiendauern
    (Kurz/Mittel/Lang) - bewusst keine festen Minutenschwellen, da
    "lang" stark vom Modus abhängt. Bei < 3 Partien mit Dauer wird
    eine leere Liste zurückgegeben (UI zeigt dann einen Hinweis statt
    einer nicht aussagekräftigen Dreiteilung).
  - `computeWinRateByColorIdentity`: Siegquote je Farbidentität über
    alle Decks mit derselben Farbkombination hinweg (Ergänzung zur
    bereits bestehenden Aufschlüsselung nach einzelnem Deck).
  Datengrundlage: `GamesRepository.watchSelfGameStats` filtert nicht
  mehr per SQL nach `playerId`, sondern lädt alle Teilnehmer jeder
  abgeschlossenen Partie und gruppiert sie in Dart nach `gameId`, um
  `participantCount` (Basis der Normierung oben) zu ermitteln, bevor
  die Zeile des Ich-Spielers herausgesucht wird. `SelfGameStatsRow`
  führt dafür zusätzlich `placement`, `startPosition`,
  `participantCount`, `durationSeconds` und `isDraw` mit. Alle vier
  neuen Auswertungen respektieren dieselben Gruppen-/Modus-Filter wie
  der Rest von `StatsScreen`.

- **Achievement-Freischalt-Logik implementiert (auf Nachfrage
  abgestimmt, dann aus dem alten mtg_stats_tracker portiert):** Zwei
  Design-Fragen vorab geklärt (siehe Standard-Regel "bei Unklarheiten
  nachfragen" - eine davon war bereits seit dem Badges-Abschnitt oben
  als offen notiert): (1) **Umfang** - nur für den Ich-Spieler
  (gewählt), nicht für jeden bekannten Spieler einzeln; (2)
  **Gruppen-Bezug** - global pro Spieler über alle Gruppen hinweg
  (gewählt), nicht getrennt je Spielgruppe.

  Die konkreten Freischalt-Regeln selbst wurden NICHT neu erfunden,
  sondern 1:1 aus dem alten mtg_stats_tracker portiert (dort bereits
  gegen echte Nutzerdaten erprobt) - gefunden unter
  `lib/features/home/controller/function/calc_*.dart` im
  Schwester-Ordner `mtg_stats_tracker` auf dem verbundenen Rechner:
  - **Sieg-Serien** (`streak_2/3/5/10`): fortlaufende Siege in Folge
    (Unentschieden zählt dabei wie überall in dieser App als Sieg für
    alle Teilnehmer); Datum = ZULETZT erreichter Zeitpunkt dieser
    Serienlänge (nicht der erste).
  - **Partien/Siege** (`matches_*`/`wins_*`): einfache Meilenstein-
    Zähler, Datum = Partie, bei der der Schwellenwert zum ersten Mal
    erreicht wurde.
  - **Farbchampion**: einfarbig mit drei Stufen (1./2./3.
    unterschiedliches GEWONNENES Deck dieser Farbe schaltet Basis-/
    "_master"-/"_champ"-Stufe frei - diese etwas unintuitive
    Namensreihenfolge stammt so aus dem Original); mehrfarbig/
    fünffarbig/farblos mit nur einer Stufe (erster Sieg mit einem Deck
    dieser Farbidentität). Da `Decks.colorIdentity` in dieser App
    bereits WUBRG-sortiert gespeichert wird, genügt zur Zuordnung eine
    einfache Kleinschreibung (`_colorKey` in `achievement_engine.dart`)
    statt der aufwendigeren String-Vergleiche des Originals.
  - **Wochentags-Serien** (`weekday_<tag>_02/03/05`): Partien am
    selben Wochentag in fortlaufend aufeinanderfolgenden Kalenderwochen
    (Abstand exakt 7 Tage); Datum = zuletzt erreichter Zeitpunkt.
  - **Spezial-Badges**: `newbie` (allererste Partie), `first_win`
    (erster Sieg), `grandios` (erster Sieg als zuletzt gestarteter
    Spieler in einer Commander-Partie mit > 3 Teilnehmern - bewusst
    nur Commander, nicht cEDH, wie im nie mit cEDH bekannten
    Original), `first_strike` (chronologisch frühestes eigenes Deck,
    dessen allererstes Spiel damit ein Sieg war), `weekend` (drei
    aufeinanderfolgende Kalendertage Fr-Sa-So mit je einer Partie),
    `win_five/ten/twentyfive_diff_decks` (Siege mit 5/10/25
    unterschiedlichen Decks).

  **Ehemalige Abweichung vom Original, seit Deck-Verleih behoben:**
  Das `shame`-Badge ("Ehrenwerte Niederlage" - Niederlage gegen einen
  Gegner, der dabei eines der EIGENEN Decks des Ich-Spielers spielt)
  war eine Zeit lang strukturell nicht erreichbar, da
  `GameParticipants.deckId` zunächst immer fest auf ein Deck des
  jeweils SELBEN Teilnehmers beschränkt war. Seit es echten
  Deck-Verleih gibt (siehe "Bekannte Fixes" - Deck-Verleih), ist das
  Badge wieder aktiv - siehe "Bekannte Fixes" für die konkrete
  Reaktivierung.

  Neue Dateien: `lib/features/achievements/model/achievement_status.
  dart` (`AchievementStatus`), `lib/features/achievements/model/
  achievement_engine.dart` (`computeAchievements`), `lib/features/
  achievements/view/screen/achievements_screen.dart`
  (`AchievementsScreen`, neuer Button "Meine Erfolge" auf dem
  Home-Screen). Keine Datenbank-/Repository-Änderungen nötig - nutzt
  denselben `GamesRepository.watchSelfGameStats`-Stream wie das
  Statistik-Dashboard, hier aber ungefiltert nach Gruppe/Modus.

## Bekannte Einschränkung: keine Datenbank-Migration

`AppDatabase.schemaVersion` steht aktuell fest auf `1`, es gibt keine
`MigrationStrategy`/`onUpgrade`. Jede Schema-Änderung (neue Spalte,
neue Tabelle, neuer Enum-Wert) wird von einer bereits bestehenden
lokalen SQLite-Datei nicht automatisch übernommen - alte Datenbanken
können dadurch inkonsistent werden (fehlende Spalten, unerwartete
Fehler beim Lesen/Schreiben). Bis eine echte Migration eingebaut ist:
nach jeder Schema-Änderung müssen App-Daten/Cache auf dem Testgerät
einmalig komplett gelöscht werden, bevor erneut getestet wird.

## Einmaliger manueller Schritt

Aus dieser Umgebung heraus kann kein `flutter create` ausgeführt
werden (kein Zugriff auf eine Flutter-Installation/Netzwerk). Daher
einmalig im Projektordner ausführen (siehe auch README.md):

```
flutter create --org com.trackandplay --project-name track_and_play .
```

Das ergänzt nur die fehlenden Plattform-Ordner (android/ios/...) und
lässt bestehende Dateien (pubspec.yaml, lib/) unangetastet.
