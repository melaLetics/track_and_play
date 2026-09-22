import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../database/app_database.dart';
import '../../../settings/controller/provider/app_settings_provider.dart';
import '../../../wheel/view/widgets/wheel_of_fortune_dialog.dart';
import '../../controller/provider/games_repository_provider.dart';
import '../../model/game_participant_draft.dart';
import '../../model/game_setup_validator.dart';
import '../../model/live_participant.dart';
import '../../model/table_seat_order.dart';

/// Live-Erfassung einer laufenden Partie: Lebenspunktezähler pro
/// Teilnehmer, Laufzeit-Timer und automatische "First Blood"-Markierung
/// (siehe GamesRepository.recordLifeChange). Eine Live-Partie ist nicht
/// pausierbar - sie läuft bis "Partie beenden" gedrückt wird. Erzwingt
/// während der gesamten Anzeigedauer Querformat UND hält den Bildschirm
/// wach (siehe initState/dispose - beides Nutzerwunsch, passend zum
/// "auf den Tisch gelegt"-Look bzw. weil sonst der Bildschirm nach
/// wenigen Sekunden Inaktivität abschaltet).
class LiveGameScreen extends ConsumerStatefulWidget {
  final int gameId;
  final GameMode mode;
  final DateTime startedAt;
  final List<LiveParticipant> participants;

  /// Nur beim FORTSETZEN einer bereits laufenden Partie gesetzt (siehe
  /// GameDetailScreen - "Partie fortsetzen"/GamesRepository.
  /// loadLiveParticipants): übernimmt die schon vor dem Verlassen des
  /// Screens gesetzte "Erste Blutung"-Markierung, damit sie nach dem
  /// Fortsetzen nicht verloren geht bzw. fälschlich neu vergeben wird.
  /// Bleibt beim erstmaligen Start einer Partie null.
  final int? firstBloodParticipantId;

  /// Aktueller Commander-Schaden-Stand je (Empfänger, Quelle, Slot)
  /// beim FORTSETZEN einer laufenden Live-Partie (siehe
  /// GamesRepository.loadCommanderDamageTotals) - analog zu
  /// [firstBloodParticipantId]. Leer beim erstmaligen Start.
  final Map<String, int> commanderDamageTotals;

  const LiveGameScreen({
    super.key,
    required this.gameId,
    required this.mode,
    required this.startedAt,
    required this.participants,
    this.firstBloodParticipantId,
    this.commanderDamageTotals = const {},
  });

  @override
  ConsumerState<LiveGameScreen> createState() => _LiveGameScreenState();
}

class _LiveGameScreenState extends ConsumerState<LiveGameScreen> {
  late final Map<int, int> _currentLife;
  int? _firstBloodParticipantId;

  /// Aktueller Commander-Schaden-Stand je (Empfänger, Quelle, Slot),
  /// siehe commanderDamageKey (live_participant.dart) - mutable
  /// Arbeitskopie von widget.commanderDamageTotals, analog zu
  /// [_currentLife].
  late final Map<String, int> _currentCommanderDamage;

  /// Summe des erhaltenen Commander-Schadens je Empfänger, über ALLE
  /// Quellen/Slots hinweg - abgeleitete Arbeitskopie neben
  /// [_currentCommanderDamage], damit [_LifeTile] die Gesamtsumme als
  /// Badge anzeigen kann (Nutzerwunsch: "Symbol ... prominenter"),
  /// ohne bei jedem build() alle Schlüssel neu aufzusummieren. Wird
  /// einmalig in initState aus widget.commanderDamageTotals berechnet
  /// und danach in [_applyCommanderDamage] inkrementell mitgeführt.
  late final Map<int, int> _commanderDamageTotalByReceiver;

  /// Reihenfolge, in der Teilnehmer zum ersten Mal auf <= 0 Lebenspunkte
  /// gefallen sind (gameParticipantId, chronologisch). Grundlage für den
  /// Platzierungs-Vorschlag beim Beenden der Partie (siehe
  /// _suggestedPlacements): wer zuerst auf <= 0 fiel, bekommt den
  /// schlechtesten vorgeschlagenen Platz. Ein Teilnehmer wird hier nur
  /// EINMAL eingetragen (beim ersten Unterschreiten), auch wenn die
  /// Lebenspunkte danach wieder steigen und erneut fallen.
  final List<int> _eliminationOrder = [];
  Timer? _ticker;
  bool _finishing = false;

  /// Anzahl bereits erfolgter Wheel-of-Fortune-Drehungen DIESER Partie
  /// (siehe WheelOfFortuneDialog.spinsCompleted/onSpinCompleted) - lebt
  /// hier statt im Dialog selbst, da dieser bei jedem Öffnen per
  /// showDialog neu erzeugt wird und seinen eigenen State beim
  /// Schließen verlieren würde. Bestimmt zusammen mit der
  /// Teilnehmerzahl die aktuelle Eskalations-Stufe (Nutzerwunsch).
  /// Startet bei 0 je Partie-Sitzung - wird eine Live-Partie verlassen
  /// und später fortgesetzt, beginnt die Eskalation neu (das Rad selbst
  /// ist bewusst reine Sitzungs-Optik ohne DB-Bezug, siehe
  /// ARCHITECTURE.md).
  int _wheelSpinsCompleted = 0;

  @override
  void initState() {
    super.initState();
    _currentLife = {
      for (final p in widget.participants) p.gameParticipantId: p.startingLife,
    };
    _currentCommanderDamage = Map.of(widget.commanderDamageTotals);
    _commanderDamageTotalByReceiver = {};
    for (final entry in _currentCommanderDamage.entries) {
      final receiverId = int.parse(entry.key.split('|')[0]);
      _commanderDamageTotalByReceiver[receiverId] =
          (_commanderDamageTotalByReceiver[receiverId] ?? 0) + entry.value;
    }
    _firstBloodParticipantId = widget.firstBloodParticipantId;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Live-Tracking wird "auf den Tisch gelegt" bedient (siehe
    // ARCHITECTURE.md) - dafür ist ausschließlich Querformat sinnvoll,
    // unabhängig von der Geräte-Rotationssperre. Wird beim Verlassen des
    // Screens in dispose() wieder aufgehoben.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Bildschirm während der Live-Partie wach halten (Nutzer-Bugreport:
    // Bildschirm ging nach wenigen Sekunden aus) - wird beim Verlassen
    // des Screens in dispose() wieder aufgehoben.
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.disable();
    super.dispose();
  }

  Duration get _elapsed => DateTime.now().difference(widget.startedAt);

  String get _elapsedLabel {
    final e = _elapsed;
    final minutes = e.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = e.inHours;
    final seconds = e.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  /// Team-Partner von [participant] in Two-Headed Giant (Nutzer-
  /// Bugreport: "bei Two Headed Giant teilen sich Team Partner einen
  /// Lebenspunktestand" - bislang wurde jede Kachel unabhängig
  /// gezählt). Leer außerhalb von Two-Headed Giant oder ohne gesetztes
  /// Team (z. B. bei alten Partien ohne Team-Zuordnung). Bewusst NICHT
  /// für Erzfeind genutzt - dort hat trotz Team-Zugehörigkeit jeder
  /// Teilnehmer weiterhin einen EIGENEN Lebenspunktestand, nur
  /// Two-Headed Giant teilt sich laut Regelwerk einen gemeinsamen Pool.
  List<LiveParticipant> _teammatesOf(LiveParticipant participant) {
    if (widget.mode != GameMode.twoHeadedGiant) return const [];
    final team = participant.team;
    if (team == null || team.isEmpty) return const [];
    return [
      for (final p in widget.participants)
        if (p.gameParticipantId != participant.gameParticipantId &&
            p.team == team)
          p,
    ];
  }

  /// Aktualisiert NUR den lokalen UI-Zustand für eine Lebenspunkte-
  /// Änderung (Zahl, "Erste Blutung", Eliminierungs-Reihenfolge) -
  /// OHNE einen DB-Schreibvorgang. Gemeinsam genutzt von [_applyDelta]
  /// (normale +/- Tipp-Flächen) und [_applyCommanderDamage]
  /// (Commander-Schaden zieht automatisch Lebenspunkte ab), damit
  /// beide exakt dieselbe Logik anwenden, aber [_applyCommanderDamage]
  /// selbst über GamesRepository.recordCommanderDamage schreibt (statt
  /// zusätzlich [recordLifeChange] aufzurufen, was den LifeEvents-
  /// Eintrag doppelt anlegen würde).
  void _updateLocalLifeState(int participantId, int newLife, int delta) {
    setState(() {
      _currentLife[participantId] = newLife;
      if (delta < 0 && _firstBloodParticipantId == null) {
        _firstBloodParticipantId = participantId;
      }
      if (newLife <= 0 && !_eliminationOrder.contains(participantId)) {
        _eliminationOrder.add(participantId);
      }
    });
  }

  Future<void> _applyDelta(LiveParticipant participant, int delta) async {
    final newLife = (_currentLife[participant.gameParticipantId] ?? 0) + delta;
    final repo = ref.read(gamesRepositoryProvider);
    // Two-Headed Giant: Team-Partner teilen sich EINEN Lebenspunktestand
    // (siehe [_teammatesOf]) - jede Änderung wird deshalb identisch auf
    // das angetippte Mitglied UND alle Team-Partner angewendet, mit
    // demselben resultierenden Wert [newLife] für alle (statt je
    // Partner separat "+delta" zu rechnen) - das heilt nebenbei auch
    // einen zuvor durch den oben genannten Bug entstandenen
    // Gleichstand-Unterschied bei einer bereits laufenden Partie beim
    // nächsten Lebenspunkte-Tipp automatisch aus. Außerhalb von
    // Two-Headed Giant liefert [_teammatesOf] eine leere Liste, das
    // Verhalten bleibt dort unverändert (nur [participant] selbst).
    for (final p in [participant, ..._teammatesOf(participant)]) {
      _updateLocalLifeState(p.gameParticipantId, newLife, delta);
      await repo.recordLifeChange(
        gameId: widget.gameId,
        gameParticipantId: p.gameParticipantId,
        delta: delta,
        resultingLife: newLife,
      );
    }
  }

  /// Trägt [delta] Commander-Schaden von [source]s Commander/Partner-
  /// Commander ([slot]) gegen [receiver] ein und zieht denselben
  /// Betrag automatisch von dessen Lebenspunkten ab (Nutzerwunsch).
  /// [delta] ist normalerweise positiv (neuer Schaden); negative Werte
  /// über den "-"-Button im Dialog korrigieren einen Fehleintrag und
  /// erhöhen die Lebenspunkte entsprechend wieder.
  Future<void> _applyCommanderDamage(
    LiveParticipant receiver,
    LiveParticipant source,
    CommanderSlot slot,
    int delta,
  ) async {
    final key = commanderDamageKey(
      receiverId: receiver.gameParticipantId,
      sourceParticipantId: source.gameParticipantId,
      slot: slot,
    );
    final newTotal = (_currentCommanderDamage[key] ?? 0) + delta;
    // Sicherheitsnetz gegen ein versehentliches Unterlaufen von 0 beim
    // Korrigieren (z. B. zweimal "-1" ohne vorherigen Schaden).
    if (newTotal < 0) return;
    final newLife = (_currentLife[receiver.gameParticipantId] ?? 0) - delta;
    setState(() {
      _currentCommanderDamage[key] = newTotal;
      _commanderDamageTotalByReceiver[receiver.gameParticipantId] =
          (_commanderDamageTotalByReceiver[receiver.gameParticipantId] ?? 0) +
              delta;
    });
    final repo = ref.read(gamesRepositoryProvider);
    // Two-Headed Giant: der Lebenspunkte-Abzug durch Commander-Schaden
    // betrifft (wie jede andere Lebenspunkte-Änderung, siehe
    // [_applyDelta]) den GESAMTEN geteilten Stand des Teams - auch wenn
    // der Commander-Schaden selbst bewusst nur beim tatsächlichen
    // EMPFÄNGER als CommanderDamageEvents-Eintrag vermerkt wird (ein
    // Team-Partner hat nicht automatisch denselben Commander-Schaden-
    // Stand erhalten, nur dieselben Lebenspunkte verloren).
    for (final p in [receiver, ..._teammatesOf(receiver)]) {
      _updateLocalLifeState(p.gameParticipantId, newLife, -delta);
      if (p.gameParticipantId == receiver.gameParticipantId) {
        await repo.recordCommanderDamage(
          gameId: widget.gameId,
          gameParticipantId: receiver.gameParticipantId,
          sourceParticipantId: source.gameParticipantId,
          commanderSlot: slot,
          delta: delta,
          resultingCommanderDamage: newTotal,
          resultingLife: newLife,
        );
      } else {
        await repo.recordLifeChange(
          gameId: widget.gameId,
          gameParticipantId: p.gameParticipantId,
          delta: -delta,
          resultingLife: newLife,
        );
      }
    }
  }

  /// Öffnet den Commander-Schaden-Dialog für [receiver] (Nutzerwunsch:
  /// "über ein Menü ... den Commander auswählen, und dort den Schaden
  /// eintragen"). Nur aufrufbar, wenn es mindestens einen Gegner gibt
  /// (siehe [_LifeTile]-Aufrufstelle unten, Button wird bei
  /// Solo-Partien gar nicht erst angezeigt).
  void _openCommanderDamageDialog(LiveParticipant receiver) {
    final opponents = [
      for (final p in widget.participants)
        if (p.gameParticipantId != receiver.gameParticipantId) p,
    ];
    showDialog<void>(
      context: context,
      builder: (_) => _CommanderDamageDialog(
        receiver: receiver,
        opponents: opponents,
        currentTotals: _currentCommanderDamage,
        onDelta: (source, slot, delta) =>
            _applyCommanderDamage(receiver, source, slot, delta),
      ),
    );
  }

  /// Ermittelt einen Platzierungs-Vorschlag aus [_eliminationOrder]: wer
  /// zuerst auf <= 0 Lebenspunkte fiel, bekommt den letzten Platz, wer
  /// als zweites fiel den vorletzten usw. Teilnehmer, die nie auf <= 0
  /// fielen ("Überlebende"), bekommen Platz 1, wenn es genau einen
  /// solchen gibt - bei mehreren Überlebenden (unentschieden im
  /// eigentlichen Sinne bei Spielende) bleibt deren Platzierung frei
  /// (null), da die Reihenfolge unter ihnen nicht ermittelbar ist. Nur
  /// ein Vorschlag: die Platzierungen bleiben im Dialog editierbar.
  Map<int, int?> _suggestedPlacements() {
    // Two-Headed Giant braucht eine eigene, team-bewusste Herleitung
    // (siehe [_suggestedTeamPlacements]) - da Team-Partner sich seit
    // dem Bugfix oben einen Lebenspunktestand teilen, fallen sie IMMER
    // gemeinsam auf <= 0 und müssten laut
    // game_setup_validator.validateGameResult auch denselben Platz
    // (1 oder 2) bekommen, nicht wie unten je nach Reihenfolge in
    // [_eliminationOrder] unterschiedliche Plätze.
    if (widget.mode == GameMode.twoHeadedGiant) {
      return _suggestedTeamPlacements();
    }
    final ids = [for (final p in widget.participants) p.gameParticipantId];
    final n = ids.length;
    final eliminated = [
      for (final id in _eliminationOrder)
        if (ids.contains(id)) id,
    ];
    final survivors = [
      for (final id in ids)
        if (!eliminated.contains(id)) id,
    ];
    final result = <int, int?>{for (final id in ids) id: null};
    for (var i = 0; i < eliminated.length; i++) {
      result[eliminated[i]] = n - i;
    }
    if (survivors.length == 1) {
      result[survivors.first] = 1;
    }
    return result;
  }

  /// Team-bewusste Variante von [_suggestedPlacements] für Two-Headed
  /// Giant: ein Team gilt als eliminiert, sobald IRGENDEIN Mitglied in
  /// [_eliminationOrder] auftaucht (dank geteilter Lebenspunkte fallen
  /// ohnehin alle Mitglieder gemeinsam auf <= 0) - bekommt dann Platz 2,
  /// das andere Team Platz 1. Genau die beiden für Two-Headed Giant
  /// gültigen Werte (siehe game_setup_validator.validateGameResult).
  /// Bei fehlender/uneindeutiger Team-Zuordnung oder wenn beide bzw.
  /// keines der Teams eliminiert wurde, bleibt die Platzierung offen
  /// (null) - bewusst nur ein Vorschlag, im Dialog weiterhin editierbar.
  Map<int, int?> _suggestedTeamPlacements() {
    final result = <int, int?>{
      for (final p in widget.participants) p.gameParticipantId: null,
    };
    final teams = <String, List<LiveParticipant>>{};
    for (final p in widget.participants) {
      final team = p.team;
      if (team == null || team.isEmpty) continue;
      teams.putIfAbsent(team, () => []).add(p);
    }
    if (teams.length != 2) return result;

    final eliminatedTeams = [
      for (final entry in teams.entries)
        if (entry.value.any(
          (p) => _eliminationOrder.contains(p.gameParticipantId),
        ))
          entry.key,
    ];
    if (eliminatedTeams.length != 1) return result;

    for (final entry in teams.entries) {
      final placement = entry.key == eliminatedTeams.first ? 2 : 1;
      for (final p in entry.value) {
        result[p.gameParticipantId] = placement;
      }
    }
    return result;
  }

  Future<void> _finishGame() async {
    final result = await showDialog<_GameResult>(
      context: context,
      builder: (context) => _ResultDialog(
        mode: widget.mode,
        participants: widget.participants,
        initialPlacements: _suggestedPlacements(),
      ),
    );
    if (result == null) return;
    setState(() => _finishing = true);
    final repo = ref.read(gamesRepositoryProvider);
    await repo.finishLiveGame(
      gameId: widget.gameId,
      startedAt: widget.startedAt,
      placements: result.placements,
      isDraw: result.isDraw,
    );
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Öffnet das Wheel-of-Fortune-Overlay (siehe WheelOfFortuneDialog) -
  /// nur aufrufbar, wenn AppSettings.wheelOfFortuneEnabled aktiv ist
  /// (siehe build, "Rad drehen"-Button in der unteren Leiste).
  void _openWheel() {
    showDialog<void>(
      context: context,
      builder: (_) => WheelOfFortuneDialog(
        participantCount: widget.participants.length,
        spinsCompleted: _wheelSpinsCompleted,
        onSpinCompleted: () => setState(() => _wheelSpinsCompleted++),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Nutzerwunsch: das Wheel-of-Fortune-Gamification-Feature ist -
    // genau wie das Tracken anderer Spieler/Gruppen - optional und
    // wird global auf dem Home-Screen ein-/ausgeschaltet (siehe
    // AppSettings.wheelOfFortuneEnabled) - der "Rad drehen"-Button
    // unten erscheint daher nur, wenn aktiviert.
    final wheelEnabled = ref.watch(settingsControllerProvider).maybeWhen(
          data: (settings) => settings.wheelOfFortuneEnabled,
          orElse: () => false,
        );
    // Nutzerwunsch: der Screen-Header (AppBar) ist "unnötig und nimmt
    // zu viel Platz ein" - gerade im landscape-gesperrten Live-Tracking
    // ist jeder Pixel Höhe für das Lebenspunkte-Grid wertvoll. Bewusst
    // KEIN schwebender Ersatz-Button ÜBER dem Grid: das Lebenspunkte-
    // Grid (_LifeGrid) füllt in jeder Sitzanordnung den kompletten
    // Bildschirm inkl. aller vier Ecken mit Tipp-Flächen (+/- je
    // Teilnehmer, siehe _LifeTile) - ein dort platzierter Button würde
    // zwangsläufig irgendeine dieser Tipp-Flächen überlappen. Verlassen
    // des Screens bleibt daher zusätzlich über die System-Navigation
    // (Zurück-Geste/-Taste) möglich; als EXPLIZITER In-App-Button dafür
    // sitzt ein Zurück-Pfeil in der Timer-Zeile der unteren Leiste
    // (Nutzerwunsch: "einen Backtick Pfeil ... damit man diesen Screen
    // verlassen kann"), da dort ohnehin fester Platz reserviert und
    // frei von Tipp-Flächen ist. Tracking läuft dabei unverändert im
    // Hintergrund weiter - siehe ARCHITECTURE.md für die bereits
    // bestehende, bekannte Einschränkung, dass eine so verlassene
    // Live-Partie im Status "inProgress" verbleibt.
    return Scaffold(
      body: SafeArea(
        child: _LifeGrid(
          participants: widget.participants,
          life: _currentLife,
          firstBloodParticipantId: _firstBloodParticipantId,
          onDelta: _applyDelta,
          // Nur bei mehr als einem Teilnehmer gibt es überhaupt
          // gegnerische Commander, gegen die Schaden eingetragen
          // werden könnte (Solo-Tracking: kein Gegner) - null lässt
          // den Button in _LifeTile ganz entfallen.
          onOpenCommanderDamage: widget.participants.length > 1
              ? _openCommanderDamageDialog
              : null,
          commanderDamageTotalByReceiver: _commanderDamageTotalByReceiver,
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              // Zurück-Pfeil neben der Uhr (Nutzerwunsch) - verlässt den
              // Screen wie die System-Zurück-Geste, das Tracking läuft im
              // Hintergrund unverändert weiter (siehe dispose(): hebt nur
              // Querformat-Sperre/Wakelock auf, die laufende Partie in der
              // DB bleibt unberührt).
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new),
                iconSize: 18,
                tooltip: 'Zurück',
                color: scheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 14),
              Icon(
                Icons.timer_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(_elapsedLabel, style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              if (wheelEnabled) ...[
                OutlinedButton.icon(
                  onPressed: _finishing ? null : _openWheel,
                  icon: const Icon(Icons.casino),
                  label: const Text('Rad drehen'),
                ),
                const SizedBox(width: 12),
              ],
              FilledButton.icon(
                onPressed: _finishing ? null : _finishGame,
                icon: const Icon(Icons.flag),
                label: const Text('Partie beenden'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lebenspunkte-Grid im "auf den Tisch gelegt"-Look (Nutzerwunsch,
/// angelehnt an eine Referenz-App mit Tisch-Layout): jeder Teilnehmer
/// bekommt im Setup (siehe GameSetupScreen._TableSeatPicker) eine
/// Tischseite (TableSide: oben/unten/links/rechts) zugewiesen, die hier
/// sowohl die POSITION (welche Zone des Grids) als auch die DREHUNG
/// seiner Kachel bestimmt - damit jeder Teilnehmer sein eigenes Feld
/// unabhängig davon lesen kann, wo das Telefon flach auf dem Tisch
/// liegt. Drehung je Seite (siehe _tile/_LifeTile): oben = 180°, unten
/// = 0°, links = 270° (damit die Textoberkante nach links zum Spieler
/// zeigt), rechts = 90° (Textoberkante nach rechts). Layout: oben/unten
/// als volle Zeilen, links/rechts als Spalten in einer mittleren Zeile
/// dazwischen - Zonen ohne Teilnehmer werden komplett weggelassen, so
/// dass eine reine Oben/Unten-Belegung (der Standardfall, siehe
/// GameSetupScreen._defaultTableSide) exakt wie das ursprüngliche
/// Zwei-Reihen-Layout aussieht. Bei EINEM Teilnehmer (Solo-Tracking)
/// entfällt jede Aufteilung/Drehung, unabhängig von der gewählten
/// Tischseite. Alte, vor Einführung des Sitzplatz-Wählers gestartete
/// Live-Partien haben für alle Teilnehmer TableSide == null - das wird
/// wie "unten" behandelt (siehe LiveParticipant-Doc), landet also in
/// einer einzelnen unrotierten Zeile statt der früheren automatischen
/// Aufteilung; unkritisch, da laut ARCHITECTURE.md nach jeder
/// Schema-Änderung ohnehin die App-Daten einmalig gelöscht werden
/// müssen. Bewusst OHNE Hintergrundbild und mit ruhigen, dem
/// App-Theme entnommenen Flächenfarben (Nutzervorgabe) - anders als
/// die Referenz-App, die je Spieler ein eigenes Hintergrundbild zeigt.
/// Die vier Schnellzugriffs-Ecken der Referenz (Schaden/Steuer/Mana/
/// Spielmarken) sind bewusst NICHT übernommen - dafür gab es in dieser
/// App zunächst noch keine Datengrundlage; mit dem Nutzer abgestimmt,
/// können sie bei Bedarf einzeln nachgezogen werden. Die
/// Commander-Schaden-Matrix wurde inzwischen nachgezogen (siehe
/// [_LifeTile]/_CommanderDamageDialog/CommanderDamageEvents,
/// ARCHITECTURE.md "Commander-Schaden im Live-Tracking") - Steuer,
/// Mana-Pool und Marken-Zähler fehlen weiterhin.
class _LifeGrid extends StatelessWidget {
  final List<LiveParticipant> participants;
  final Map<int, int> life;
  final int? firstBloodParticipantId;
  final void Function(LiveParticipant participant, int delta) onDelta;

  /// null blendet den Commander-Schaden-Button in [_LifeTile] aus
  /// (siehe Aufrufstelle in [_LiveGameScreenState.build] - nur bei
  /// Solo-Partien ohne Gegner).
  final ValueChanged<LiveParticipant>? onOpenCommanderDamage;

  /// Summe des erhaltenen Commander-Schadens je Empfänger, siehe
  /// _LiveGameScreenState._commanderDamageTotalByReceiver - für das
  /// Badge auf dem Commander-Schaden-Button in [_LifeTile].
  final Map<int, int> commanderDamageTotalByReceiver;

  const _LifeGrid({
    required this.participants,
    required this.life,
    required this.firstBloodParticipantId,
    required this.onDelta,
    required this.onOpenCommanderDamage,
    required this.commanderDamageTotalByReceiver,
  });

  TableSide _sideOf(LiveParticipant p) => p.tableSide ?? TableSide.bottom;

  @override
  Widget build(BuildContext context) {
    if (participants.length <= 1) {
      return Row(
        children: [
          for (final p in participants) Expanded(child: _tile(p, quarterTurns: 0)),
        ],
      );
    }
    // Innerhalb jeder Seite nach Startreihenfolge sortiert (siehe
    // sortForTableSide) - Nutzerwunsch: "Man spielt im Uhrzeigersinn,
    // so dass Person 1 rechts von Person 2 sitzt usw." Gilt für JEDE
    // Sitzanordnung, auch manuell über den Sitzplatz-Wähler im Setup
    // zusammengestellte - die reine Hinzufüge-Reihenfolge der
    // Teilnehmer spielt für die Anzeige-Position keine Rolle mehr.
    final top = sortForTableSide(
      [for (final p in participants) if (_sideOf(p) == TableSide.top) p],
      TableSide.top,
      (p) => p.startPosition,
    );
    final bottom = sortForTableSide(
      [for (final p in participants) if (_sideOf(p) == TableSide.bottom) p],
      TableSide.bottom,
      (p) => p.startPosition,
    );
    final left = sortForTableSide(
      [for (final p in participants) if (_sideOf(p) == TableSide.left) p],
      TableSide.left,
      (p) => p.startPosition,
    );
    final right = sortForTableSide(
      [for (final p in participants) if (_sideOf(p) == TableSide.right) p],
      TableSide.right,
      (p) => p.startPosition,
    );

    final hasMiddleRow = left.isNotEmpty || right.isNotEmpty;

    return Column(
      children: [
        if (top.isNotEmpty) Expanded(child: _row(top, quarterTurns: 2)),
        if (hasMiddleRow)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (left.isNotEmpty)
                  Expanded(child: _column(left, quarterTurns: 3)),
                if (right.isNotEmpty)
                  Expanded(child: _column(right, quarterTurns: 1)),
              ],
            ),
          ),
        if (bottom.isNotEmpty) Expanded(child: _row(bottom, quarterTurns: 0)),
      ],
    );
  }

  Widget _row(List<LiveParticipant> row, {required int quarterTurns}) {
    return Row(
      children: [
        for (final p in row) Expanded(child: _tile(p, quarterTurns: quarterTurns)),
      ],
    );
  }

  Widget _column(List<LiveParticipant> col, {required int quarterTurns}) {
    return Column(
      children: [
        for (final p in col) Expanded(child: _tile(p, quarterTurns: quarterTurns)),
      ],
    );
  }

  Widget _tile(LiveParticipant p, {required int quarterTurns}) {
    return _LifeTile(
      participant: p,
      life: life[p.gameParticipantId] ?? 0,
      quarterTurns: quarterTurns,
      isFirstBlood: firstBloodParticipantId == p.gameParticipantId,
      onDelta: (delta) => onDelta(p, delta),
      onOpenCommanderDamage: onOpenCommanderDamage == null
          ? null
          : () => onOpenCommanderDamage!(p),
      commanderDamageTotal:
          commanderDamageTotalByReceiver[p.gameParticipantId] ?? 0,
    );
  }
}

/// Eine einzelne Spieler-Kachel im Lebenspunkte-Grid (siehe
/// [_LifeGrid]): von oben nach unten Name (+ "Erste Blutung"-Marker),
/// Tipp-Fläche "+" (Lebenspunkte erhöhen), große Lebenspunkte-Zahl,
/// Tipp-Fläche "-" (Lebenspunkte senken) - genau die vom Nutzer
/// gewünschte Anordnung ("oberhalb ein Plus, unterhalb ein Minus").
/// Einfaches Antippen ändert die Lebenspunkte um 1, langes Drücken um
/// 5 (übernimmt die bisherigen -5/-1/+1/+5-Schnellwahl-Buttons, nur
/// platzsparender - passt so in die kompakte Tisch-Kachel). [quarterTurns]
/// dreht die GESAMTE Kachel um die angegebene Zahl von 90°-Schritten
/// (RotatedBox statt Transform.rotate - vertauscht bei 90°/270° korrekt
/// Breite/Höhe, das Layout darunter bleibt unverändert simpel), damit
/// ein Teilnehmer an einer beliebigen Tischseite (siehe TableSide/
/// _LifeGrid) sein Feld richtig herum liest: 0 = unten (unrotiert),
/// 2 = oben (180°), 3 = links (270°, Textoberkante zeigt nach links),
/// 1 = rechts (90°, Textoberkante zeigt nach rechts).
class _LifeTile extends StatelessWidget {
  final LiveParticipant participant;
  final int life;
  final int quarterTurns;
  final bool isFirstBlood;
  final ValueChanged<int> onDelta;

  /// null blendet den Button aus (siehe _LifeGrid._tile).
  final VoidCallback? onOpenCommanderDamage;

  /// Summe des bereits erhaltenen Commander-Schadens (über alle
  /// Quellen/Slots) - als Badge-Zahl auf dem Button (Nutzerwunsch:
  /// "Symbol ... prominenter"), 0 wenn noch keiner eingetragen wurde.
  final int commanderDamageTotal;

  const _LifeTile({
    required this.participant,
    required this.life,
    required this.quarterTurns,
    required this.isFirstBlood,
    required this.onDelta,
    required this.onOpenCommanderDamage,
    required this.commanderDamageTotal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accentColor = scheme.primary.withValues(alpha: .8);
    final tileBody = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isFirstBlood) ...[
                  Icon(Icons.bloodtype, size: 14, color: scheme.error),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    participant.displayName,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Nutzerwunsch: "+" und "-" stehen rechts/links neben der
          // Lebenspunkteanzeige statt darüber/darunter - "-" links,
          // "+" rechts. Diese Anordnung wird EINMAL im unrotierten
          // Inhalt festgelegt und gilt dadurch automatisch korrekt aus
          // Sicht jedes Spielers, auch nach der RotatedBox unten (siehe
          // bisher schon so gehandhabtes Muster).
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => onDelta(-1),
                    onLongPress: () => onDelta(-5),
                    child: Center(
                      child: Icon(Icons.remove, size: 26, color: accentColor),
                    ),
                  ),
                ),
                Text(
                  '$life',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: life <= 0 ? scheme.error : scheme.onSurface,
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => onDelta(1),
                    onLongPress: () => onDelta(5),
                    child: Center(
                      child: Icon(Icons.add, size: 26, color: accentColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // Commander-Schaden-Button (Nutzerwunsch: "prominenter" und "statt
    // neben dem Namen rechts unten") - als eigenständiger, größerer
    // Kreis-Button über der Kachel platziert statt in der Namenszeile,
    // mit Badge für die bereits erhaltene Gesamtsumme. Liegt in der
    // rechten unteren Ecke der "+"-Tippfläche; da er als eigener
    // InkWell mit begrenzter Fläche ÜBER dem großen "+"-InkWell im
    // Stack liegt, fängt er Tipps in seinem eigenen Bereich ab, der
    // Rest der "+"-Fläche bleibt normal bedienbar. Bewusst erst NACH
    // [tileBody] im Stack (= oben drauf), damit er nicht vom großen
    // "+"-InkWell überdeckt wird. Nur sichtbar, wenn es überhaupt
    // Gegner gibt (siehe _LifeGrid._tile).
    final content = onOpenCommanderDamage == null
        ? tileBody
        : Stack(
            children: [
              tileBody,
              Positioned(
                right: 6,
                bottom: 6,
                child: Material(
                  color: scheme.secondaryContainer,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    onTap: onOpenCommanderDamage,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Badge(
                        isLabelVisible: commanderDamageTotal > 0,
                        label: Text('$commanderDamageTotal'),
                        child: Icon(
                          Icons.shield,
                          size: 24,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
    return quarterTurns == 0
        ? content
        : RotatedBox(quarterTurns: quarterTurns, child: content);
  }
}

/// Dialog zum Eintragen von Commander-Schaden für [receiver]
/// (Nutzerwunsch): pro Gegner ([opponents]) eine Zeile je Commander
/// (Commander + ggf. Partner-Commander separat, siehe
/// LiveParticipant.commanderName/secondCommanderName) mit +/-
/// Zählern. Führt eine LOKALE Arbeitskopie von [currentTotals]
/// (übergeben aus _LiveGameScreenState._currentCommanderDamage), damit
/// die Zahlen im Dialog sofort auf Tippen reagieren, unabhängig davon,
/// dass der eigentliche Live-Screen dahinter separat (asynchron über
/// [onDelta]) aktualisiert und persistiert.
class _CommanderDamageDialog extends StatefulWidget {
  final LiveParticipant receiver;
  final List<LiveParticipant> opponents;
  final Map<String, int> currentTotals;
  final void Function(LiveParticipant source, CommanderSlot slot, int delta)
      onDelta;

  const _CommanderDamageDialog({
    required this.receiver,
    required this.opponents,
    required this.currentTotals,
    required this.onDelta,
  });

  @override
  State<_CommanderDamageDialog> createState() =>
      _CommanderDamageDialogState();
}

class _CommanderDamageDialogState extends State<_CommanderDamageDialog> {
  late Map<String, int> _totals;

  @override
  void initState() {
    super.initState();
    _totals = Map.of(widget.currentTotals);
  }

  String _keyFor(LiveParticipant source, CommanderSlot slot) =>
      commanderDamageKey(
        receiverId: widget.receiver.gameParticipantId,
        sourceParticipantId: source.gameParticipantId,
        slot: slot,
      );

  void _change(LiveParticipant source, CommanderSlot slot, int delta) {
    final key = _keyFor(source, slot);
    final next = (_totals[key] ?? 0) + delta;
    if (next < 0) return;
    setState(() => _totals[key] = next);
    widget.onDelta(source, slot, delta);
  }

  @override
  Widget build(BuildContext context) {
    // Eigener Dialog statt AlertDialog: AlertDialog begrenzt die Breite
    // auf einen schmalen Standardwert und stapelt die Gegner in einer
    // einzelnen, vertikal scrollenden Spalte - bei 3 Gegnern im
    // Querformat (typische Live-Tracking-Ausrichtung) reicht die Höhe
    // dann nicht mehr aus. Stattdessen: feste Kartenbreite pro Gegner
    // in einem Wrap, das die verfügbare Bildschirmbreite ausnutzt, so
    // dass mehrere Gegner i. d. R. in eine Zeile passen; bei größeren
    // Pods oder schmaleren Bildschirmen fällt es auf mehrere Zeilen mit
    // Scroll-Fallback zurück (siehe Nutzerfeedback: "bei drei Spielern
    // schon scrollen muss").
    final screenSize = MediaQuery.sizeOf(context);
    final maxDialogWidth = screenSize.width - 32;
    final maxDialogHeight = screenSize.height - 32;
    const cardWidth = 220.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Commander-Schaden für ${widget.receiver.displayName}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Fertig',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final source in widget.opponents)
                        SizedBox(
                          width: cardWidth,
                          child: _opponentCard(source),
                        ),
                      if (widget.opponents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Keine Gegner in dieser Partie.'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opponentCard(LiveParticipant source) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.displayName,
              style: Theme.of(context).textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            _commanderRow(
              source,
              CommanderSlot.primary,
              // Fällt auf einen generischen Platzhalter zurück, statt
              // den Gegner ganz aus der Auswahl zu entfernen, wenn kein
              // Commander hinterlegt ist (anonymer Teilnehmer oder Deck
              // ohne Commander-Angabe) - siehe LiveParticipant.commanderName.
              source.commanderName ?? 'Commander (unbekannt)',
            ),
            if (source.secondCommanderName != null &&
                source.secondCommanderName!.isNotEmpty)
              _commanderRow(
                source,
                CommanderSlot.partner,
                source.secondCommanderName!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _commanderRow(
    LiveParticipant source,
    CommanderSlot slot,
    String label,
  ) {
    final total = _totals[_keyFor(source, slot)] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: total <= 0 ? null : () => _change(source, slot, -1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$total',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _change(source, slot, 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _GameResult {
  final Map<int, int> placements;
  final bool isDraw;

  const _GameResult({required this.placements, required this.isDraw});
}

/// Platzierungs-Dialog beim Beenden einer Live-Partie: dieselben Regeln
/// wie beim manuellen Nachtragen (siehe game_setup_validator.dart) -
/// bei Two-Headed Giant/Erzfeind per Team-/Erzfeind-Sieger-Auswahl, bei
/// Commander/cEDH per individueller Platzierung je Teilnehmer.
class _ResultDialog extends StatefulWidget {
  final GameMode mode;
  final List<LiveParticipant> participants;

  /// Vorausberechneter Platzierungs-Vorschlag (gameParticipantId -> Platz
  /// oder null bei Uneindeutigkeit), siehe
  /// _LiveGameScreenState._suggestedPlacements. Wird nur für den
  /// individuellen Platzierungs-Modus (Commander/cEDH) als Startwert
  /// übernommen, nicht für Team-Modi (Archenemy/2HG), deren Platzierung
  /// ausschließlich über die Sieger-Auswahl gesetzt wird.
  final Map<int, int?>? initialPlacements;

  const _ResultDialog({
    required this.mode,
    required this.participants,
    this.initialPlacements,
  });

  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  late Map<int, int?> _placements;
  bool _isDraw = false;

  bool get _isTeamMode =>
      widget.mode == GameMode.archenemy || widget.mode == GameMode.twoHeadedGiant;

  @override
  void initState() {
    super.initState();
    _placements = {
      for (final p in widget.participants)
        p.gameParticipantId:
            _isTeamMode ? null : widget.initialPlacements?[p.gameParticipantId],
    };
  }

  /// Ob mindestens einer der vorbelegten Startwerte aus einem
  /// Platzierungs-Vorschlag stammt (siehe initialPlacements) - steuert,
  /// ob im Dialog ein entsprechender Hinweistext angezeigt wird.
  bool get _hasSuggestion =>
      !_isTeamMode &&
      (widget.initialPlacements?.values.any((v) => v != null) ?? false);

  void _setDraw(bool value) {
    setState(() {
      _isDraw = value;
      if (value) {
        for (final p in widget.participants) {
          _placements[p.gameParticipantId] = 1;
        }
      }
    });
  }

  void _setTeamWinner(String winningTeam) {
    setState(() {
      for (final p in widget.participants) {
        _placements[p.gameParticipantId] = p.team == winningTeam ? 1 : 2;
      }
    });
  }

  void _setArchenemyWinner(bool archenemyWins) {
    setState(() {
      for (final p in widget.participants) {
        final isArchenemy = p.team == 'archenemy';
        _placements[p.gameParticipantId] = (isArchenemy == archenemyWins) ? 1 : 2;
      }
    });
  }

  void _setPlacement(int gameParticipantId, int value) {
    if (value < 1) return;
    setState(() => _placements[gameParticipantId] = value);
  }

  String? get _error {
    final drafts = [
      for (final p in widget.participants)
        GameParticipantDraft(
          startPosition: p.startPosition,
          team: p.team,
          placement: _placements[p.gameParticipantId],
        ),
    ];
    return validateGameResult(
      mode: widget.mode,
      participants: drafts,
      isDraw: _isDraw,
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Partie beenden'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDraw,
                onChanged: (value) => _setDraw(value ?? false),
                title: const Text('Unentschieden'),
              ),
              if (!_isDraw && widget.mode == GameMode.twoHeadedGiant)
                Row(
                  children: [
                    const Text('Sieger-Team:'),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => _setTeamWinner('A'),
                      child: const Text('Team A'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _setTeamWinner('B'),
                      child: const Text('Team B'),
                    ),
                  ],
                ),
              if (!_isDraw && widget.mode == GameMode.archenemy)
                Row(
                  children: [
                    const Text('Sieger:'),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => _setArchenemyWinner(true),
                      child: const Text('Erzfeind'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _setArchenemyWinner(false),
                      child: const Text('Team'),
                    ),
                  ],
                ),
              if (!_isDraw && !_isTeamMode && _hasSuggestion)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Platzierung anhand der Lebenspunkte vorgeschlagen - '
                    'bitte prüfen und bei Bedarf anpassen.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (!_isDraw && !_isTeamMode)
                for (final p in widget.participants)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(p.displayName)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setPlacement(
                            p.gameParticipantId,
                            (_placements[p.gameParticipantId] ?? 1) - 1,
                          ),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${_placements[p.gameParticipantId] ?? '-'}'),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setPlacement(
                            p.gameParticipantId,
                            (_placements[p.gameParticipantId] ?? 0) + 1,
                          ),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: error != null
              ? null
              : () => Navigator.of(context).pop(
                    _GameResult(
                      placements: {
                        for (final entry in _placements.entries)
                          entry.key: entry.value!,
                      },
                      isDraw: _isDraw,
                    ),
                  ),
          child: const Text('Bestätigen'),
        ),
      ],
    );
  }
}
