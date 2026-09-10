import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../controller/provider/games_repository_provider.dart';
import '../../model/game_mode_labels.dart';
import '../../model/game_participant_draft.dart';
import '../../model/game_setup_validator.dart';
import '../../model/live_participant.dart';

/// Live-Erfassung einer laufenden Partie: Lebenspunktezähler pro
/// Teilnehmer, Laufzeit-Timer und automatische "First Blood"-Markierung
/// (siehe GamesRepository.recordLifeChange). Eine Live-Partie ist nicht
/// pausierbar - sie läuft bis "Partie beenden" gedrückt wird. Erzwingt
/// während der gesamten Anzeigedauer Querformat (siehe initState/dispose
/// - Nutzerwunsch, passend zum "auf den Tisch gelegt"-Look).
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

  const LiveGameScreen({
    super.key,
    required this.gameId,
    required this.mode,
    required this.startedAt,
    required this.participants,
    this.firstBloodParticipantId,
  });

  @override
  ConsumerState<LiveGameScreen> createState() => _LiveGameScreenState();
}

class _LiveGameScreenState extends ConsumerState<LiveGameScreen> {
  late final Map<int, int> _currentLife;
  int? _firstBloodParticipantId;

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

  @override
  void initState() {
    super.initState();
    _currentLife = {
      for (final p in widget.participants) p.gameParticipantId: p.startingLife,
    };
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

  Future<void> _applyDelta(LiveParticipant participant, int delta) async {
    final newLife = (_currentLife[participant.gameParticipantId] ?? 0) + delta;
    setState(() {
      _currentLife[participant.gameParticipantId] = newLife;
      if (delta < 0 && _firstBloodParticipantId == null) {
        _firstBloodParticipantId = participant.gameParticipantId;
      }
      if (newLife <= 0 &&
          !_eliminationOrder.contains(participant.gameParticipantId)) {
        _eliminationOrder.add(participant.gameParticipantId);
      }
    });
    final repo = ref.read(gamesRepositoryProvider);
    await repo.recordLifeChange(
      gameId: widget.gameId,
      gameParticipantId: participant.gameParticipantId,
      delta: delta,
      resultingLife: newLife,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(gameModeLabels[widget.mode] ?? widget.mode.name),
      ),
      body: SafeArea(
        child: _LifeGrid(
          participants: widget.participants,
          life: _currentLife,
          firstBloodParticipantId: _firstBloodParticipantId,
          onDelta: _applyDelta,
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
              Icon(
                Icons.timer_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(_elapsedLabel, style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
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
/// Spielmarken) sind bewusst NICHT übernommen - dafür gibt es in
/// dieser App noch keine Datengrundlage (kein Schadens-Log, keine
/// Kommandeur-Schaden-Matrix, kein Mana-Pool, keine Marken-Zähler);
/// mit dem Nutzer abgestimmt, können bei Bedarf später einzeln
/// nachgezogen werden.
class _LifeGrid extends StatelessWidget {
  final List<LiveParticipant> participants;
  final Map<int, int> life;
  final int? firstBloodParticipantId;
  final void Function(LiveParticipant participant, int delta) onDelta;

  const _LifeGrid({
    required this.participants,
    required this.life,
    required this.firstBloodParticipantId,
    required this.onDelta,
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
    final top = [
      for (final p in participants) if (_sideOf(p) == TableSide.top) p,
    ];
    final bottom = [
      for (final p in participants) if (_sideOf(p) == TableSide.bottom) p,
    ];
    final left = [
      for (final p in participants) if (_sideOf(p) == TableSide.left) p,
    ];
    final right = [
      for (final p in participants) if (_sideOf(p) == TableSide.right) p,
    ];

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

  const _LifeTile({
    required this.participant,
    required this.life,
    required this.quarterTurns,
    required this.isFirstBlood,
    required this.onDelta,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accentColor = scheme.primary.withValues(alpha: .8);
    final content = DecoratedBox(
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
          Expanded(
            child: InkWell(
              onTap: () => onDelta(1),
              onLongPress: () => onDelta(5),
              child: Center(
                child: Icon(Icons.add, size: 26, color: accentColor),
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
              onTap: () => onDelta(-1),
              onLongPress: () => onDelta(-5),
              child: Center(
                child: Icon(Icons.remove, size: 26, color: accentColor),
              ),
            ),
          ),
        ],
      ),
    );
    return quarterTurns == 0
        ? content
        : RotatedBox(quarterTurns: quarterTurns, child: content);
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
