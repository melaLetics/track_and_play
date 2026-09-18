import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../database/app_database.dart';
import '../../export/model/export_bundle.dart';
import '../model/participant_override.dart';
import '../../games/model/game_mode_labels.dart';
import '../model/import_preview.dart';
import '../model/import_selection.dart';
import '../model/import_warning.dart';

/// Ein Partie-Teilnehmer, bereits vollständig aufgelöst (Spieler/
/// Deck-Zuordnung, siehe ImportService.performImport) - aber noch
/// NICHT in die Datenbank eingefügt. Wird VOR dem Anlegen der Partie
/// selbst ermittelt, damit die automatische Gruppen-Zuordnung (siehe
/// dort) schon die aufgelösten Spieler-ids kennt.
typedef _ResolvedParticipant = ({
  int? playerId,
  int? deckId,
  String? anonymousLabel,
  String? anonymousColorIdentity,
  bool isWinner,
  String? team,
  int? startingLife,
  int? startPosition,
  int? placement,
});

/// Parst und importiert ein [ExportBundle] (aus Datei ODER QR-Code -
/// beide liefern denselben rohen JSON-String, siehe
/// ImportWizardScreen) in die Datenbank.
///
/// Duplikat-Erkennung (mit dem Nutzer abgestimmt): Spieler/Decks/
/// Gruppen werden per Namens-Abgleich (case-insensitive) gegen den
/// aktuellen Datenbestand vorab als "vermutlich schon vorhanden"
/// markiert und in der Vorschau standardmäßig abgewählt - der Nutzer
/// kann trotzdem manuell zustimmen. Partien werden NIE automatisch
/// abgeglichen (ohne geräteübergreifende IDs zu fehleranfällig),
/// sondern immer einzeln mit Datum/Modus/Teilnehmern zur Auswahl
/// angezeigt, standardmäßig aber alle vorausgewählt - ABER (mit dem
/// Nutzer abgestimmte Ergänzung) nur, wenn der eigene Self-Player
/// tatsächlich teilgenommen hat (siehe [selfPlayerName] in
/// [buildPreview]); Partien ohne eigene Teilnahme erscheinen gar
/// nicht erst in der Vorschau.
class ImportService {
  final AppDatabase db;

  const ImportService(this.db);

  ExportBundle parseBundle(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException(
        'Das ist kein gültiges Export-Bundle (kein lesbares JSON).',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Das ist kein gültiges Export-Bundle (unerwartetes Format).',
      );
    }
    return ExportBundle.fromJson(decoded);
  }

  /// [selfPlayerName] (Name des lokalen Self-Players, siehe
  /// AppSettings.selfPlayerId/selfPlayerProvider) filtert sowohl
  /// [bundle].groups als auch [bundle].games (Namens-Abgleich wie beim
  /// übrigen Import, case-insensitive):
  /// - Gruppen: nur Gruppen, in denen dieser Name als Mitglied
  ///   vorkommt, werden importiert - Gruppen ohne eigene Mitgliedschaft
  ///   sind für den personenbezogenen Tracker irrelevant (mit dem
  ///   Nutzer abgestimmte Vorgabe).
  /// - Partien: nur Partien, an denen dieser Name tatsächlich als
  ///   Teilnehmer beteiligt war, werden importiert (dieselbe Vorgabe).
  ///
  /// Beide Kategorien werden bei Nichterfüllung komplett aus der
  /// Vorschau gefiltert (kein [ImportPreviewEntry], nicht wählbar,
  /// nicht importierbar) statt nur standardmäßig abgewählt zu sein.
  /// Wird kein Name übergeben (z. B. Self-Player noch nicht geladen),
  /// entfallen beide Filter komplett statt versehentlich alles
  /// auszublenden.
  Future<ImportPreview> buildPreview(
    ExportBundle bundle, {
    String? selfPlayerName,
  }) async {
    final existingPlayers = await db.select(db.players).get();
    final existingPlayerNames = <String>{
      for (final p in existingPlayers) p.name.toLowerCase(),
    };
    final existingPlayerNameByLower = <String, String>{
      for (final p in existingPlayers) p.name.toLowerCase(): p.name,
    };
    final existingDecks = await db.select(db.decks).get();
    final ownerNameByPlayerId = <int, String>{
      for (final p in existingPlayers) p.id: p.name,
    };
    final existingDeckByKey = <String, Deck>{
      for (final d in existingDecks)
        '${(ownerNameByPlayerId[d.ownerPlayerId] ?? '').toLowerCase()}||'
            '${d.name.toLowerCase()}': d,
    };
    final existingGroups = await db.select(db.groups).get();
    final existingGroupNames = <String>{
      for (final g in existingGroups) g.name.toLowerCase(),
    };
    final existingGroupNameByLower = <String, String>{
      for (final g in existingGroups) g.name.toLowerCase(): g.name,
    };

    final players = <ImportPreviewEntry>[];
    final selectedPlayers = <int>{};
    for (var i = 0; i < bundle.players.length; i++) {
      final p = bundle.players[i];
      final duplicate = existingPlayerNames.contains(p.name.toLowerCase());
      players.add(
        ImportPreviewEntry(
          index: i,
          title: p.name,
          likelyDuplicate: duplicate,
          matchedExistingLabel:
              duplicate ? existingPlayerNameByLower[p.name.toLowerCase()] : null,
        ),
      );
      if (!duplicate) selectedPlayers.add(i);
    }

    final decks = <ImportPreviewEntry>[];
    final selectedDecks = <int>{};
    for (var i = 0; i < bundle.decks.length; i++) {
      final d = bundle.decks[i];
      final key = '${d.ownerName.toLowerCase()}||${d.name.toLowerCase()}';
      final existingDeck = existingDeckByKey[key];
      final duplicate = existingDeck != null;
      decks.add(
        ImportPreviewEntry(
          index: i,
          title: d.name,
          subtitle: d.ownerName,
          likelyDuplicate: duplicate,
          matchedExistingLabel: duplicate ? existingDeck.name : null,
          deckFieldDiffs:
              duplicate ? _deckFieldDiffs(existingDeck, d) : const [],
        ),
      );
      if (!duplicate) selectedDecks.add(i);
    }

    final selfNameLower = selfPlayerName?.trim().toLowerCase();
    final hasSelfFilter = selfNameLower != null && selfNameLower.isNotEmpty;

    final groups = <ImportPreviewEntry>[];
    final selectedGroups = <int>{};
    for (var i = 0; i < bundle.groups.length; i++) {
      final g = bundle.groups[i];
      if (hasSelfFilter) {
        final selfIsMember = g.memberNames.any(
          (n) => n.toLowerCase() == selfNameLower,
        );
        // Gruppen ohne eigene Mitgliedschaft tauchen gar nicht erst in
        // der Vorschau auf (siehe buildPreview-Dartdoc oben) - kein
        // ImportPreviewEntry, kein Auswahl-Eintrag, kein Import.
        if (!selfIsMember) continue;
      }
      final duplicate = existingGroupNames.contains(g.name.toLowerCase());
      groups.add(
        ImportPreviewEntry(
          index: i,
          title: g.name,
          subtitle:
              g.memberNames.isEmpty ? null : '${g.memberNames.length} Mitglieder',
          likelyDuplicate: duplicate,
          matchedExistingLabel:
              duplicate ? existingGroupNameByLower[g.name.toLowerCase()] : null,
        ),
      );
      if (!duplicate) selectedGroups.add(i);
    }

    final games = <ImportPreviewEntry>[];
    final selectedGames = <int>{};
    for (var i = 0; i < bundle.games.length; i++) {
      final g = bundle.games[i];
      if (hasSelfFilter) {
        final selfParticipated = g.participants.any(
          (p) => p.playerName?.toLowerCase() == selfNameLower,
        );
        // Partien ohne eigene Teilnahme tauchen gar nicht erst in der
        // Vorschau auf (siehe buildPreview-Dartdoc oben) - kein
        // ImportPreviewEntry, kein Auswahl-Eintrag, kein Import.
        if (!selfParticipated) continue;
      }
      final names = [
        for (final p in g.participants) p.playerName ?? p.anonymousLabel ?? '?',
      ];
      games.add(
        ImportPreviewEntry(
          index: i,
          title: '${_formatDate(g.playedAt)} · ${_modeLabel(g.mode)}',
          subtitle: names.isEmpty ? null : names.join(', '),
        ),
      );
      selectedGames.add(i);
    }

    return ImportPreview(
      bundle: bundle,
      players: players,
      decks: decks,
      groups: groups,
      games: games,
      defaultSelection: ImportSelection(
        selectedPlayerIndexes: selectedPlayers,
        selectedDeckIndexes: selectedDecks,
        selectedGroupIndexes: selectedGroups,
        selectedGameIndexes: selectedGames,
      ),
    );
  }

  Future<ImportResult> performImport(
    ExportBundle bundle,
    ImportSelection selection,
  ) {
    return db.transaction(() async {
      final warnings = <ImportWarning>[];

      // Name -> id, zuerst mit dem aktuellen Datenbestand vorbelegt,
      // dann von tatsächlich neu importierten Einträgen überschrieben
      // ("frischester Treffer gewinnt" - siehe Klassendokumentation:
      // ausgewählte Bundle-Einträge binden nachfolgende Referenzen
      // innerhalb desselben Bundles an sich selbst, nicht ausgewählte
      // Duplikate fallen auf den bereits vorhandenen Eintrag zurück).
      final playerIdByName = <String, int>{
        for (final p in await db.select(db.players).get())
          p.name.toLowerCase(): p.id,
      };

      var playersImported = 0;
      var playersMerged = 0;
      for (final i in selection.selectedPlayerIndexes) {
        if (selection.mergePlayerIndexes.contains(i)) {
          // Nutzer hat im "gleiche Person?"-Dialog bestätigt, dass es
          // sich um eine bereits bestehende lokale Person handelt
          // (siehe ImportSelection.mergePlayerIndexes) - playerIdByName
          // ist oben bereits mit dem GESAMTEN vorhandenen Datenbestand
          // vorbelegt und zeigt für diesen Namen daher schon auf den
          // richtigen bestehenden Datensatz. Kein Insert, keine
          // Überschreibung - sonst entstünde exakt der gemeldete Bug
          // (zweite Person, Decks/Partien an der falschen Person).
          playersMerged++;
          continue;
        }
        final pe = bundle.players[i];
        final id = await db.into(db.players).insert(
              PlayersCompanion.insert(
                name: pe.name,
                archived: Value(pe.archived),
              ),
            );
        playerIdByName[pe.name.toLowerCase()] = id;
        playersImported++;
      }

      // Bereits bestehende Decks VOR der Import-Schleife per
      // Besitzer+Name-Schlüssel erfasst (derselbe Schlüssel wie in
      // buildPreview/_deckFieldDiffs) - Grundlage für den unten
      // benötigten "bestehendes Deck aktualisieren statt neu
      // anlegen"-Zweig (siehe ImportSelection.mergeDeckIndexes).
      final existingPlayerNameById = <int, String>{
        for (final p in await db.select(db.players).get()) p.id: p.name,
      };
      final existingDeckIdByKey = <String, int>{
        for (final d in await db.select(db.decks).get())
          '${(existingPlayerNameById[d.ownerPlayerId] ?? '').toLowerCase()}||'
              '${d.name.toLowerCase()}': d.id,
      };

      // Bugfix (Nutzer-Feedback nach dem QR-Deck-Bugfix: "Beim Import
      // wird stets behauptet, dass das Deck nicht zugeordnet werden
      // könne. Sowohl Spieler als auch Deck sind angelegt."):
      // deckIdByKey MUSS - genau wie playerIdByName oben - mit dem
      // bereits vorhandenen lokalen Bestand vorbelegt werden, sonst
      // kann ein Partie-Teilnehmer NIE einem bereits existierenden
      // Deck zugeordnet werden, das nicht zufällig auch Teil DIESES
      // Bundles ist (z. B. jeder reine Partie-QR-Import, siehe
      // buildGameQrBundle - dessen bundle.decks ist immer leer).
      // Frisch in diesem Bundle importierte/gemergte Decks
      // überschreiben unten weiterhin ihren jeweiligen Schlüssel
      // ("frischester Treffer gewinnt", analog zu playerIdByName).
      final deckIdByKey = <String, int>{...existingDeckIdByKey};
      var decksImported = 0;
      var decksMerged = 0;
      for (final i in selection.selectedDeckIndexes) {
        final de = bundle.decks[i];
        final ownerId = playerIdByName[de.ownerName.toLowerCase()];
        if (ownerId == null) {
          warnings.add(
            ImportWarning(
              category: ImportWarningCategory.deck,
              message: 'Deck "${de.name}" übersprungen: Besitzer '
                  '"${de.ownerName}" nicht importiert/gefunden.',
            ),
          );
          continue;
        }
        DeckBuildType? buildType;
        if (de.buildType != null) {
          try {
            buildType = DeckBuildType.values.byName(de.buildType!);
          } on ArgumentError {
            buildType = null;
          }
        }
        final key = '${de.ownerName.toLowerCase()}||${de.name.toLowerCase()}';

        if (selection.mergeDeckIndexes.contains(i)) {
          // Nutzer hat im "Deck aktualisieren?"-Dialog bestätigt, dass
          // die abweichenden Werte aus dem Import übernommen werden
          // sollen (siehe ImportSelection.mergeDeckIndexes) - kein
          // neuer Deck-Datensatz, stattdessen werden die inhaltlichen
          // Felder des bestehenden Decks überschrieben. archived NICHT
          // mit überschrieben (rein lokaler Anzeige-Zustand, kein
          // Deck-Inhalt - siehe _deckFieldDiffs).
          final existingId = existingDeckIdByKey[key];
          if (existingId != null) {
            await (db.update(db.decks)..where((t) => t.id.equals(existingId)))
                .write(
              DecksCompanion(
                colorIdentity: Value(de.colorIdentity),
                commanderName: Value(de.commanderName),
                secondCommanderName: Value(de.secondCommanderName),
                buildType: Value(buildType),
                bracket: Value(de.bracket),
                isProxy: Value(de.isProxy),
                isTournamentLegal: Value(de.isTournamentLegal),
                deckLink: Value(de.deckLink),
              ),
            );
            deckIdByKey[key] = existingId;
            decksMerged++;
            continue;
          }
          // Der erwartete bestehende Datensatz wurde nicht gefunden
          // (z. B. zwischenzeitlich gelöscht) - dann wie ein normaler
          // Import unten fortfahren, statt die Aktualisierung
          // stillschweigend zu verwerfen.
        }

        final id = await db.into(db.decks).insert(
              DecksCompanion.insert(
                ownerPlayerId: ownerId,
                name: de.name,
                colorIdentity: Value(de.colorIdentity),
                commanderName: Value(de.commanderName),
                secondCommanderName: Value(de.secondCommanderName),
                buildType: Value(buildType),
                bracket: Value(de.bracket),
                isProxy: Value(de.isProxy),
                isTournamentLegal: Value(de.isTournamentLegal),
                deckLink: Value(de.deckLink),
                archived: Value(de.archived),
              ),
            );
        deckIdByKey[key] = id;
        decksImported++;
      }

      final groupIdByName = <String, int>{
        for (final g in await db.select(db.groups).get())
          g.name.toLowerCase(): g.id,
      };
      var groupsImported = 0;
      var groupsMerged = 0;
      for (final i in selection.selectedGroupIndexes) {
        final ge = bundle.groups[i];
        if (selection.mergeGroupIndexes.contains(i)) {
          // Nutzer hat im "gleiche Gruppe?"-Dialog bestätigt, dass es
          // sich um eine bereits bestehende lokale Gruppe handelt
          // (siehe ImportSelection.mergeGroupIndexes) - spiegelbildlich
          // zum Spieler-Merge oben: kein neuer Gruppen-Datensatz, aber
          // fehlende Mitgliedschaften werden in die bestehende Gruppe
          // übernommen (sonst gingen Mitgliederinformationen aus dem
          // Bundle verloren, nur weil die Gruppe selbst schon lokal
          // existiert). groupIdByName ist oben bereits mit dem
          // gesamten vorhandenen Datenbestand vorbelegt und liefert
          // für diesen (per Definition bereits vorhandenen)
          // Gruppennamen den richtigen bestehenden Datensatz.
          final existingGroupId = groupIdByName[ge.name.toLowerCase()];
          if (existingGroupId != null) {
            for (final memberName in ge.memberNames) {
              final memberId = playerIdByName[memberName.toLowerCase()];
              if (memberId == null) continue;
              await db.into(db.playerGroupMemberships).insert(
                    PlayerGroupMembershipsCompanion.insert(
                      playerId: memberId,
                      groupId: existingGroupId,
                    ),
                    mode: InsertMode.insertOrIgnore,
                  );
            }
            groupsMerged++;
          }
          continue;
        }
        final id = await db.into(db.groups).insert(
              GroupsCompanion.insert(name: ge.name, archived: Value(ge.archived)),
            );
        groupIdByName[ge.name.toLowerCase()] = id;
        groupsImported++;
        for (final memberName in ge.memberNames) {
          final memberId = playerIdByName[memberName.toLowerCase()];
          if (memberId == null) continue;
          await db.into(db.playerGroupMemberships).insert(
                PlayerGroupMembershipsCompanion.insert(
                  playerId: memberId,
                  groupId: id,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }

      // Spieler -> Menge seiner Gruppen-ids, fuer die automatische
      // Gruppen-Zuordnung von Partien ohne (auflösbare) Gruppenangabe
      // im Bundle (siehe inferSharedGroupId unten, mit dem Nutzer
      // abgestimmte Ergaenzung) - einmal VOR der Partien-Schleife
      // geladen; enthaelt dank derselben Transaktion bereits eben erst
      // importierte Gruppen-Mitgliedschaften.
      final groupIdsByPlayerId = <int, Set<int>>{};
      for (final m in await db.select(db.playerGroupMemberships).get()) {
        groupIdsByPlayerId.putIfAbsent(m.playerId, () => {}).add(m.groupId);
      }

      /// Liefert die EINDEUTIGE Gruppe, der ALLE übergebenen Spieler
      /// bereits gemeinsam angehören - oder null, wenn mindestens ein
      /// Teilnehmer anonym ist (kein playerId, also nicht sicher
      /// zuordenbar), die Spieler gar keine gemeinsame Gruppe teilen,
      /// oder mehr als eine Gruppe infrage kommt (dann bewusst keine
      /// Annahme statt einer willkürlichen Wahl).
      int? inferSharedGroupId(List<int?> playerIds) {
        if (playerIds.isEmpty || playerIds.any((id) => id == null)) {
          return null;
        }
        Set<int>? shared;
        for (final id in playerIds) {
          final groupsOfPlayer = groupIdsByPlayerId[id] ?? const <int>{};
          shared = shared == null
              ? Set<int>.from(groupsOfPlayer)
              : shared.intersection(groupsOfPlayer);
          if (shared.isEmpty) return null;
        }
        return shared!.length == 1 ? shared.first : null;
      }

      var gamesImported = 0;
      for (final i in selection.selectedGameIndexes) {
        final ge = bundle.games[i];
        GameMode mode;
        try {
          mode = GameMode.values.byName(ge.mode);
        } on ArgumentError {
          warnings.add(
            ImportWarning(
              category: ImportWarningCategory.game,
              message: 'Partie vom ${_formatDate(ge.playedAt)} übersprungen: '
                  'unbekannter Modus "${ge.mode}" (vermutlich aus einer '
                  'neueren App-Version).',
            ),
          );
          continue;
        }
        GameEntryMode entryMode;
        try {
          entryMode = GameEntryMode.values.byName(ge.entryMode);
        } on ArgumentError {
          entryMode = GameEntryMode.manual;
        }

        // Teilnehmer werden jetzt VOR dem Anlegen der Partie aufgelöst
        // (statt wie bisher direkt beim Einfügen), damit die
        // automatische Gruppen-Zuordnung unten schon die aufgelösten
        // Spieler-ids kennt.
        final resolved = <_ResolvedParticipant>[];
        final overridesForGame = selection.participantOverrides[i] ?? const {};
        for (var pIndex = 0; pIndex < ge.participants.length; pIndex++) {
          final pe = ge.participants[pIndex];
          final override = overridesForGame[pIndex];

          int? playerId;
          int? deckId;
          var anonymousLabel = pe.anonymousLabel;
          var anonymousColorIdentity = pe.anonymousColorIdentity;

          if (override != null &&
              override.mode == ParticipantOverrideMode.assign) {
            // Nutzer hat diesen Teilnehmer beim Import manuell einem
            // bereits bekannten lokalen Spieler (z. B. sich selbst)
            // zugeordnet und optional eines von dessen eigenen Decks
            // gewählt - siehe ParticipantOverride/GameImportTile. Hat
            // Vorrang vor jeder Namens-basierten Auflösung.
            playerId = override.playerId;
            deckId = override.deckId;
          } else if (override != null &&
              override.mode == ParticipantOverrideMode.anonymous) {
            // Nutzer hat explizit "anonym bleiben" gewählt - auch wenn
            // playerName im Bundle gesetzt und lokal auflösbar wäre.
            anonymousLabel ??= pe.playerName;
            anonymousColorIdentity ??=
                pe.colorIdentity.isNotEmpty ? pe.colorIdentity : null;
          } else if (pe.playerName != null) {
            playerId = playerIdByName[pe.playerName!.toLowerCase()];
            if (playerId != null && pe.deckName != null) {
              // Deck-Verleih: gehoert das Deck laut Bundle einem ANDEREN
              // Spieler (pe.deckOwnerName gesetzt, siehe
              // export_bundle.dart), wird der Deck-Schluessel ueber
              // dessen Namen statt ueber den Teilnehmer aufgeloest - der
              // Teilnehmer (playerId) bleibt davon unberuehrt.
              deckId = deckIdByKey[
                  '${(pe.deckOwnerName ?? pe.playerName)!.toLowerCase()}||'
                  '${pe.deckName!.toLowerCase()}'];
            }
            if (playerId == null) {
              // Spieler wurde nicht importiert/gefunden - die Teilnahme
              // bleibt trotzdem erhalten, aber als anonymer Eintrag
              // (siehe GameParticipants-Tabelle), damit die Partie
              // nicht stillschweigend einen Teilnehmer verliert.
              anonymousLabel ??= pe.playerName;
              anonymousColorIdentity ??=
                  pe.colorIdentity.isNotEmpty ? pe.colorIdentity : null;
              warnings.add(
                ImportWarning(
                  category: ImportWarningCategory.participant,
                  message: 'Teilnehmer "${pe.playerName}" in Partie vom '
                      '${_formatDate(ge.playedAt)} als anonym übernommen '
                      '(Spieler nicht importiert/gefunden).',
                ),
              );
            } else if (pe.deckName != null && deckId == null) {
              // Nutzer-Bugreport: "beim Export einer Partie via QR Code
              // ... fehlten die Informationen zu den Decks." deckIdByKey
              // ist jetzt (Folge-Bugfix, siehe oben bei dessen
              // Initialisierung) mit dem GESAMTEN bereits vorhandenen
              // lokalen Deck-Bestand vorbelegt, nicht mehr nur mit
              // Decks, die zufällig auch Teil DIESES Bundles sind -
              // ein Partie-Teilnehmer wird also auch dann korrekt
              // zugeordnet, wenn Spieler UND Deck beim Import bereits
              // lokal existieren. Dieser Zweig hier greift folglich nur
              // noch, wenn wirklich KEIN lokales Deck mit passendem
              // Schlüssel (Besitzer+Name, case-insensitiv) existiert -
              // z. B. weil das Deck auf dem exportierenden Gerät anders
              // heißt/einem anderen Besitzer zugeordnet ist, oder
              // schlicht noch nie importiert wurde. Der Deck-NAME
              // (pe.deckName) ist dafür immerhin in der Vorschau
              // sichtbar (siehe GameImportTile). Die Farbidentität wird
              // trotzdem nicht verloren - siehe den allgemeinen
              // Fallback direkt unten vor resolved.add (Nutzerwunsch:
              // "Sollte ein Deck nicht gefunden werden, dann sollte
              // zumindest die Farbidentität des Decks anstelle der
              // Deckinformation stehen.").
              warnings.add(
                ImportWarning(
                  category: ImportWarningCategory.deck,
                  message: 'Deck "${pe.deckName}" von "${pe.playerName}" in '
                      'Partie vom ${_formatDate(ge.playedAt)} konnte keinem '
                      'lokalen Deck zugeordnet werden - stattdessen wurde '
                      'nur die Farbidentität übernommen. Bitte bei Bedarf '
                      'oben manuell zuordnen.',
                ),
              );
            }
          }

          // Nutzerwunsch: "Sollte ein Deck nicht gefunden werden, dann
          // sollte zumindest die Farbidentität des Decks anstelle der
          // Deckinformation stehen." Greift für JEDEN Fall, in dem am
          // Ende kein deckId verknüpft ist und noch keine Farbe gesetzt
          // wurde (weder über den "Spieler nicht gefunden"-Zweig noch
          // über "anonym bleiben" oben) - deckt also sowohl die
          // automatische Zuordnung ohne Treffer als auch eine manuelle
          // Override-Zuordnung ohne gewähltes Deck ("Kein Deck angeben"
          // im _DeckPicker) ab. pe.colorIdentity wird laut
          // export_bundle.dart IMMER mitgeliefert (bei bekannten
          // Teilnehmern vom Quell-Deck übernommen). Kein neues
          // Datenbankfeld nötig: GameParticipantView._toParticipantView
          // (games_repository.dart) liest anonymousColorIdentity
          // ohnehin schon unabhängig von playerId/isAnonymous als
          // generischen "kein verknüpftes Deck"-Fallback
          // (`deck?.colorIdentity ?? participant.anonymousColorIdentity
          // ?? ''`) - dasselbe Feld war bisher nur beim SCHREIBEN
          // fälschlich auf anonyme Teilnehmer beschränkt.
          if (deckId == null &&
              anonymousColorIdentity == null &&
              pe.colorIdentity.isNotEmpty) {
            anonymousColorIdentity = pe.colorIdentity;
          }

          resolved.add((
            playerId: playerId,
            deckId: deckId,
            anonymousLabel: anonymousLabel,
            anonymousColorIdentity: anonymousColorIdentity,
            isWinner: pe.isWinner,
            team: pe.team,
            startingLife: pe.startingLife,
            startPosition: pe.startPosition,
            placement: pe.placement,
          ));
        }

        // Gruppen-Zuordnung: zuerst die im Bundle angegebene Gruppe
        // (falls vorhanden UND lokal auflösbar), sonst - mit dem
        // Nutzer abgestimmte Ergänzung - automatisch die Gruppe, der
        // ALLE Teilnehmer dieser Partie bereits eindeutig gemeinsam
        // angehören (siehe inferSharedGroupId).
        final groupId = (ge.groupName != null
                ? groupIdByName[ge.groupName!.toLowerCase()]
                : null) ??
            inferSharedGroupId([for (final r in resolved) r.playerId]);

        final gameId = await db.into(db.games).insert(
              GamesCompanion.insert(
                playedAt: ge.playedAt,
                mode: mode,
                notes: Value(ge.notes),
                groupId: Value(groupId),
                entryMode: entryMode,
                status: GameStatus.completed,
                durationSeconds: Value(ge.durationSeconds),
                isDraw: Value(ge.isDraw),
              ),
            );

        final participantIds = <int>[];
        for (final r in resolved) {
          final participantId = await db.into(db.gameParticipants).insert(
                GameParticipantsCompanion.insert(
                  gameId: gameId,
                  playerId: Value(r.playerId),
                  deckId: Value(r.deckId),
                  anonymousLabel:
                      Value(r.playerId == null ? r.anonymousLabel : null),
                  // Nutzerwunsch: "Sollte ein Deck nicht gefunden
                  // werden, dann sollte zumindest die Farbidentität
                  // des Decks anstelle der Deckinformation stehen." -
                  // anders als anonymousLabel (das nur für einen
                  // wirklich anonymen Teilnehmer Sinn ergibt, ein
                  // bekannter Teilnehmer hat ja bereits playerId/Namen)
                  // wird dieses Feld jetzt an r.deckId statt an
                  // r.playerId geknüpft: es ist der generische
                  // "kein verknüpftes Deck"-Fallback, den
                  // GameParticipantView._toParticipantView
                  // (games_repository.dart) beim Lesen ohnehin schon
                  // unabhängig davon konsultiert, ob der Teilnehmer
                  // anonym oder bekannt ist. r.anonymousColorIdentity
                  // ist oben (siehe deckId==null-Fallback vor
                  // resolved.add) bereits so berechnet, dass es nur
                  // dann einen Wert trägt, wenn kein Deck verknüpft
                  // ist - die deckId-Prüfung hier ist daher primär zur
                  // Absicherung/Dokumentation der Absicht.
                  anonymousColorIdentity: Value(
                      r.deckId == null ? r.anonymousColorIdentity : null),
                  isWinner: Value(r.isWinner),
                  team: Value(r.team),
                  startingLife: Value(r.startingLife),
                  startPosition: Value(r.startPosition),
                  placement: Value(r.placement),
                ),
              );
          participantIds.add(participantId);
        }

        final fbIndex = ge.firstBloodParticipantIndex;
        if (fbIndex != null && fbIndex >= 0 && fbIndex < participantIds.length) {
          await (db.update(db.games)..where((g) => g.id.equals(gameId))).write(
            GamesCompanion(
              firstBloodParticipantId: Value(participantIds[fbIndex]),
            ),
          );
        }
        gamesImported++;
      }

      return ImportResult(
        playersImported: playersImported,
        decksImported: decksImported,
        groupsImported: groupsImported,
        gamesImported: gamesImported,
        playersMerged: playersMerged,
        decksMerged: decksMerged,
        groupsMerged: groupsMerged,
        warnings: warnings,
      );
    });
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.'
      '${dt.year}';

  String _modeLabel(String mode) {
    try {
      final m = GameMode.values.byName(mode);
      return gameModeLabels[m] ?? mode;
    } on ArgumentError {
      return mode;
    }
  }
}

/// Menschlich lesbare Beschreibung der inhaltlichen Feld-Unterschiede
/// zwischen einem bereits bestehenden lokalen Deck [existing] und
/// einem im Bundle enthaltenen [DeckExport] [incoming] - eine Zeile
/// pro abweichendem Feld (z. B. "Commander: Alela → Atraxa"), leere
/// Liste bei vollständiger Übereinstimmung. Grundlage für den "Deck
/// aktualisieren?"-Dialog im ImportWizardScreen (Nutzerwunsch: erkennt
/// beim Teilen eines überarbeiteten Decks per QR-Code/Datei, dass es
/// lokal schon existiert, gleicht ALLE inhaltlichen Felder ab -
/// Commander, Farbidentität, Bracket, turnierlegal, Link, Proxy,
/// Bauart - und fragt bei Abweichung nach, ob gemergt werden soll).
/// Bewusst NICHT verglichen: Name/Besitzer (das ist der
/// Abgleichs-Schlüssel selbst, siehe buildPreview/performImport) und
/// [Deck.archived] (rein lokaler Anzeige-Zustand, kein Deck-Inhalt).
List<String> _deckFieldDiffs(Deck existing, DeckExport incoming) {
  String fmt(Object? value) {
    if (value == null || value == '') return '-';
    if (value is bool) return value ? 'Ja' : 'Nein';
    return value.toString();
  }

  final diffs = <String>[];
  void check(String label, Object? existingValue, Object? incomingValue) {
    if (existingValue == incomingValue) return;
    diffs.add('$label: ${fmt(existingValue)} → ${fmt(incomingValue)}');
  }

  check('Commander', existing.commanderName, incoming.commanderName);
  check(
    'Zweiter Commander',
    existing.secondCommanderName,
    incoming.secondCommanderName,
  );
  check('Farbidentität', existing.colorIdentity, incoming.colorIdentity);
  check('Bauart', existing.buildType?.name, incoming.buildType);
  check('Bracket', existing.bracket, incoming.bracket);
  check('Proxy', existing.isProxy, incoming.isProxy);
  check(
    'Turnierlegal',
    existing.isTournamentLegal,
    incoming.isTournamentLegal,
  );
  check('Link', existing.deckLink, incoming.deckLink);

  return diffs;
}
