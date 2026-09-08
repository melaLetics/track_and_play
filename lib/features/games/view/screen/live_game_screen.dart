import 'dart:async';

import 'package:flutter/material.dart';
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
/// pausierbar - sie läuft bis "Partie beenden" gedrückt wird.
class LiveGameScreen extends ConsumerStatefulWidget {
  final int gameId;
  final GameMode mode;
  final DateTime startedAt;
  final List<LiveParticipant> participants;

  const LiveGameScreen({
    super.key,
    required this.gameId,
    required this.mode,
    required this.startedAt,
    required this.participants,
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(gameModeLabels[widget.mode] ?? widget.mode.name),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Text(
                  _elapsedLabel,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final p in widget.participants)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.displayName,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              if (_firstBloodParticipantId ==
                                  p.gameParticipantId)
                                const Chip(
                                  avatar: Icon(Icons.bloodtype, size: 18),
                                  label: Text('First Blood'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                onPressed: () => _applyDelta(p, -5),
                                icon: const Icon(Icons.remove_circle),
                              ),
                              IconButton(
                                onPressed: () => _applyDelta(p, -1),
                                icon: const Icon(Icons.remove),
                              ),
                              Text(
                                '${_currentLife[p.gameParticipantId]}',
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              IconButton(
                                onPressed: () => _applyDelta(p, 1),
                                icon: const Icon(Icons.add),
                              ),
                              IconButton(
                                onPressed: () => _applyDelta(p, 5),
                                icon: const Icon(Icons.add_circle),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'live_game_fab',
        onPressed: _finishing ? null : _finishGame,
        icon: const Icon(Icons.flag),
        label: const Text('Partie beenden'),
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
