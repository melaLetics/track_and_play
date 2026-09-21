import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';
import '../../../groups/controller/provider/groups_repository_provider.dart';
import '../../../players/controller/provider/players_repository_provider.dart';
import '../../../settings/controller/provider/app_settings_provider.dart';
import '../../controller/provider/games_repository_provider.dart';
import '../../model/game_mode_labels.dart';
import '../../model/game_participant_draft.dart';
import '../../model/game_setup_validator.dart';
import '../../model/table_seat_order.dart';
import '../../model/table_side_labels.dart';
import '../widgets/add_anonymous_participant_dialog.dart';
import '../widgets/add_known_participant_dialog.dart';
import '../widgets/select_deck_dialog.dart';
import 'live_game_screen.dart';

/// Gemeinsamer Einstieg für das Erfassen einer neuen Partie: Modus,
/// optionale Gruppe und Teilnehmer (bekannt oder anonym, inkl.
/// Startposition und - je nach Modus - Team) werden hier
/// zusammengestellt, bevor entweder manuell gespeichert (inkl.
/// Platzierung) oder eine Live-Erfassung gestartet wird. Nur bei
/// Live-Erfassung zusätzlich: Start-Lebenspunkte und ein visueller
/// Sitzplatz-Wähler (_TableSeatPicker), der festlegt, an welcher
/// Tischseite jeder Teilnehmer im Live-Grid erscheint (siehe
/// LiveGameScreen).
class GameSetupScreen extends ConsumerStatefulWidget {
  const GameSetupScreen({super.key});

  @override
  ConsumerState<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends ConsumerState<GameSetupScreen> {
  GameMode _mode = GameMode.commander;
  GameEntryMode _entryMode = GameEntryMode.manual;
  int? _groupId;
  DateTime _playedAt = DateTime.now();
  final _notesController = TextEditingController();
  int _startingLife = 40;
  bool _isDraw = false;
  final List<GameParticipantDraft> _participants = [];
  bool _selfAddAttempted = false;

  bool get _isTeamMode =>
      _mode == GameMode.archenemy || _mode == GameMode.twoHeadedGiant;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addSelfIfNeeded() async {
    if (_selfAddAttempted) return;
    _selfAddAttempted = true;
    final self = await ref.read(selfPlayerProvider.future);
    if (self != null && mounted) {
      setState(() {
        _participants.add(
          _withDefaults(
            GameParticipantDraft(playerId: self.id, playerName: self.name),
          ),
        );
      });
    }
  }

  int _nextStartPosition() {
    final used = _participants.map((p) => p.startPosition ?? 0);
    final max = used.isEmpty ? 0 : used.reduce((a, b) => a > b ? a : b);
    return max + 1;
  }

  GameParticipantDraft _withDefaults(GameParticipantDraft draft) {
    final startPosition = _nextStartPosition();
    String? team;
    if (_mode == GameMode.twoHeadedGiant) {
      team = _participants.length.isEven ? 'A' : 'B';
    }
    return draft.copyWith(
      startPosition: startPosition,
      team: team,
      tableSide: _defaultTableSide(),
      // Ist "Unentschieden" schon aktiv, muss auch ein NEU hinzugefügter
      // Teilnehmer sofort placement:1 bekommen - sonst bliebe er ohne
      // Platzierung, obwohl die Platzierungs-Eingabe bei Unentschieden
      // ausgeblendet ist und der Nutzer sie somit nicht nachtragen könnte.
      placement: _isDraw ? 1 : null,
    );
  }

  /// Ausgangsbelegung für neu hinzugefügte Teilnehmer im Sitzplatz-
  /// Wähler (siehe _TableSeatPicker): gleicht oben/unten aus - exakt
  /// dieselbe Verteilung, die das Live-Grid früher automatisch ohne
  /// Wähler vorgenommen hat (erste Hälfte oben, Rest unten), nur
  /// inkrementell statt in einem Rutsch berechnet, da Teilnehmer
  /// einzeln hinzugefügt werden. Links/Rechts bleiben reine manuelle
  /// Wahl über den Wähler - dafür gibt es keinen automatischen
  /// Standardwert. Bei Gleichstand (auch ganz am Anfang) wird "unten"
  /// bevorzugt.
  TableSide _defaultTableSide() {
    final topCount =
        _participants.where((p) => p.tableSide == TableSide.top).length;
    final bottomCount = _participants
        .where((p) => (p.tableSide ?? TableSide.bottom) == TableSide.bottom)
        .length;
    return topCount < bottomCount ? TableSide.top : TableSide.bottom;
  }

  void _setTableSide(int index, TableSide side) {
    setState(() {
      _participants[index] = _participants[index].copyWith(tableSide: side);
    });
  }

  /// Ordnet ALLE Teilnehmer automatisch anhand ihrer Startreihenfolge um
  /// den Tisch an (Nutzerwunsch: "Man spielt im Uhrzeigersinn, so dass
  /// Person 1 rechts von Person 2 sitzt usw." - aktuell hängen
  /// Sitzplatz und Startreihenfolge komplett unabhängig voneinander).
  /// Überschreibt bestehende Sitzplatz-Zuordnungen komplett - einzelne
  /// Teilnehmer lassen sich danach weiterhin wie gewohnt über den
  /// Sitzplatz-Wähler manuell umsetzen (siehe
  /// _TableSeatPicker/_setTableSide/_swapStartPositions), diese
  /// Funktion liefert nur einen (auf Wunsch wiederholbaren) Vorschlag.
  ///
  /// Verteilung der Tischseiten: bewusst NUR zwei Seiten (unten/oben)
  /// statt aller vier (Nutzerwunsch: "wäre es schön, würde man nicht
  /// auf alle vier Seiten des Tisches verteilt werden, sondern auf zwei
  /// Tischseiten") - links/rechts bleiben reine manuelle Optionen im
  /// Sitzplatz-Wähler. Die erste (aufgerundete) Hälfte der Teilnehmer
  /// in Zugreihenfolge kommt auf "unten", der Rest auf "oben" - KEIN
  /// striktes Reihum (1,3,5.. unten / 2,4,6.. oben), sondern
  /// BLOCKWEISE aufeinanderfolgende Zugreihenfolge je Seite: das
  /// entspricht einem simplen rechteckigen Tisch mit nur zwei langen
  /// Seiten, an dem man im Uhrzeigersinn reihum Platz nimmt - erst die
  /// gesamte untere Seite (siehe sortForTableSide: Zugreihenfolge
  /// verläuft dort von rechts nach links), dann am linken Ende
  /// "umlaufend" die gesamte obere Seite (dort von links nach rechts) -
  /// und vom rechten Ende der oberen Seite wieder zurück zum rechten
  /// Ende der unteren Seite, wo Teilnehmer 1 sitzt (siehe
  /// table_seat_order.dart für die vollständige Geometrie-Herleitung).
  void _autoArrangeSeats() {
    if (_participants.isEmpty) return;
    final sortedIndexes = [for (var i = 0; i < _participants.length; i++) i]
      ..sort((a, b) {
        final posA = _participants[a].startPosition ?? 0;
        final posB = _participants[b].startPosition ?? 0;
        return posA.compareTo(posB);
      });
    final bottomCount = (sortedIndexes.length / 2).ceil();
    setState(() {
      for (var rank = 0; rank < sortedIndexes.length; rank++) {
        final index = sortedIndexes[rank];
        final side = rank < bottomCount ? TableSide.bottom : TableSide.top;
        _participants[index] = _participants[index].copyWith(tableSide: side);
      }
    });
  }

  /// Tauscht die Startposition (Zugreihenfolge) zweier Teilnehmer, die
  /// aktuell auf DERSELBEN Tischseite sitzen (Nutzerwunsch: "zwei
  /// Personen, die an einer Tischseite sitzen, [sollen] miteinander die
  /// Plätze tauschen können"). Da die Position INNERHALB einer Seite
  /// ausschließlich aus der Startposition abgeleitet wird (siehe
  /// sortForTableSide), gibt es keinen separaten "Sitzplatz-Rang" zum
  /// Tauschen - stattdessen werden direkt die beiden Startpositions-
  /// Werte vertauscht. Wirkt sich NUR auf die relative Zugreihenfolge
  /// dieser beiden Teilnehmer aus (alle anderen Startpositionen bleiben
  /// unverändert, die Eindeutigkeit 1..N bleibt automatisch gewahrt) -
  /// wird von _TableSeatPicker aus dem Popup-Menü eines Sitzplatz-Chips
  /// heraus aufgerufen (nur Einträge derselben Seite werden dort
  /// angeboten).
  void _swapStartPositions(int indexA, int indexB) {
    setState(() {
      final posA = _participants[indexA].startPosition;
      final posB = _participants[indexB].startPosition;
      _participants[indexA] = _participants[indexA].copyWith(
        startPosition: posB,
      );
      _participants[indexB] = _participants[indexB].copyWith(
        startPosition: posA,
      );
    });
  }

  Set<int> get _knownPlayerIds =>
      _participants.map((p) => p.playerId).whereType<int>().toSet();

  Future<void> _addKnownParticipant() async {
    final draft = await showAddKnownParticipantDialog(
      context,
      excludePlayerIds: _knownPlayerIds,
      groupId: _groupId,
    );
    if (draft != null) {
      setState(() => _participants.add(_withDefaults(draft)));
    }
  }

  Future<void> _addAnonymousParticipant() async {
    final draft = await showAddAnonymousParticipantDialog(context);
    if (draft != null) {
      setState(() => _participants.add(_withDefaults(draft)));
    }
  }

  /// Ändert nachträglich das Deck eines bereits hinzugefügten bekannten
  /// Teilnehmers (z. B. des automatisch vorbelegten Ich-Spielers) -
  /// bisher ging das nur über den Umweg "entfernen und über den
  /// Bekannte-Spieler-Dialog neu hinzufügen".
  Future<void> _changeDeck(int index) async {
    final draft = _participants[index];
    final playerId = draft.playerId;
    if (playerId == null) return;
    final selection = await showSelectDeckDialog(
      context,
      playerId: playerId,
      playerName: draft.displayName,
    );
    if (selection == null) return;
    setState(() {
      _participants[index] = draft.withDeck(
        deckId: selection.deckId,
        deckName: selection.deckName,
        colorIdentity: selection.colorIdentity,
        deckOwnerPlayerId: selection.ownerPlayerId,
        deckOwnerName: selection.ownerName,
      );
    });
  }

  void _removeParticipant(int index) {
    setState(() => _participants.removeAt(index));
  }

  void _setStartPosition(int index, int value) {
    if (value < 1) return;
    setState(() {
      _participants[index] = _participants[index].copyWith(
        startPosition: value,
      );
    });
  }

  void _setPlacement(int index, int value) {
    if (value < 1) return;
    setState(() {
      _participants[index] = _participants[index].copyWith(placement: value);
    });
  }

  void _setTeam(int index, String team) {
    setState(() {
      _participants[index] = _participants[index].copyWith(team: team);
    });
  }

  void _setArchenemy(int index) {
    setState(() {
      for (var i = 0; i < _participants.length; i++) {
        final isChosen = i == index;
        _participants[i] = _participants[i].copyWith(
          team: isChosen ? 'archenemy' : 'team',
        );
      }
    });
  }

  void _setTeamWinner(String winningTeam) {
    setState(() {
      for (var i = 0; i < _participants.length; i++) {
        final p = _participants[i];
        _participants[i] = p.copyWith(placement: p.team == winningTeam ? 1 : 2);
      }
    });
  }

  void _setArchenemyWinner(bool archenemyWins) {
    setState(() {
      for (var i = 0; i < _participants.length; i++) {
        final p = _participants[i];
        final isArchenemy = p.team == 'archenemy';
        _participants[i] = p.copyWith(
          placement: (isArchenemy == archenemyWins) ? 1 : 2,
        );
      }
    });
  }

  void _setDraw(bool value) {
    setState(() {
      _isDraw = value;
      if (value) {
        for (var i = 0; i < _participants.length; i++) {
          _participants[i] = _participants[i].copyWith(placement: 1);
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _playedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _playedAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _playedAt.hour,
          _playedAt.minute,
        );
      });
    }
  }

  String? get _validationError {
    if (_participants.isEmpty) return 'Noch keine Teilnehmer hinzugefügt.';
    if (_entryMode == GameEntryMode.manual) {
      return validateGameResult(
        mode: _mode,
        participants: _participants,
        isDraw: _isDraw,
      );
    }
    return validateGameSetup(mode: _mode, participants: _participants);
  }

  Future<void> _saveManual() async {
    final repo = ref.read(gamesRepositoryProvider);
    final notes = _notesController.text.trim();
    // Sicherheitsnetz: Bei einem Unentschieden gelten laut App-Konvention
    // alle Teilnehmer als Sieger (placement == 1, siehe
    // GameParticipantDraft.isWinner) - unabhängig davon, ob/wann genau
    // die einzelnen Teilnehmer hinzugefügt wurden.
    final participants = _isDraw
        ? [for (final p in _participants) p.copyWith(placement: 1)]
        : _participants;
    await repo.createManualGame(
      playedAt: _playedAt,
      mode: _mode,
      notes: notes.isEmpty ? null : notes,
      groupId: _groupId,
      participants: participants,
      isDraw: _isDraw,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _startLive() async {
    final startedAt = DateTime.now();
    final draftsWithLife = [
      for (final p in _participants) p.copyWith(startingLife: _startingLife),
    ];
    final repo = ref.read(gamesRepositoryProvider);
    final (gameId, _) = await repo.startLiveGame(
      mode: _mode,
      groupId: _groupId,
      participants: draftsWithLife,
    );
    // Nach dem Anlegen einmal frisch aus der DB laden statt die
    // LiveParticipant-Liste hier manuell nachzubauen (Nutzerwunsch-
    // Ergänzung Commander-Schaden): loadLiveParticipants joint bereits
    // gegen Decks für commanderName/secondCommanderName (siehe
    // games_repository.dart) - das hier zu duplizieren wäre
    // fehleranfällig. Die frisch angelegten Teilnehmer haben noch
    // keine LifeEvents, liefern also ohnehin exakt _startingLife
    // zurück wie zuvor die manuelle Konstruktion.
    final liveParticipants = await repo.loadLiveParticipants(gameId);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LiveGameScreen(
            gameId: gameId,
            mode: _mode,
            startedAt: startedAt,
            participants: liveParticipants,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _addSelfIfNeeded();
    final groupsAsync = ref.watch(allGroupsProvider);
    final settingsAsync = ref.watch(settingsControllerProvider);
    final trackOtherPlayers = settingsAsync.maybeWhen(
      data: (settings) => settings.trackOtherPlayers,
      orElse: () => false,
    );
    final error = _validationError;

    return Scaffold(
      appBar: AppBar(title: const Text('Neue Partie')),
      // SafeArea(top: false, ...) - Bugreport: auf manchen Android-
      // Telefonen (Geräte-Navigationsleiste - Gesten-Balken oder
      // 3-Tasten-Leiste am unteren Bildschirmrand, je nach System-UI-
      // Modus) wurde der untere Teil des Screens, insbesondere der
      // abschließende "Manuell speichern"-/"Live-Erfassung starten"-
      // Button, davon verdeckt: eine reine `ListView` mit fixem
      // `padding: EdgeInsets.all(16)` berücksichtigt die System-
      // Navigationsleiste NICHT automatisch (das würde nur bei einer
      // `bottomNavigationBar` geschehen, siehe LiveGameScreen). `top:
      // false`, weil die AppBar den oberen Safe-Area-Bereich (Status-
      // Leiste/Notch) bereits selbst berücksichtigt - ein zusätzliches
      // Top-Inset hier würde nur unnötigen doppelten Abstand erzeugen.
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          SegmentedButton<GameEntryMode>(
            segments: const [
              ButtonSegment(
                value: GameEntryMode.manual,
                label: Text('Manuell nachtragen'),
                icon: Icon(Icons.edit_note),
              ),
              ButtonSegment(
                value: GameEntryMode.live,
                label: Text('Live erfassen'),
                icon: Icon(Icons.play_circle_outline),
              ),
            ],
            selected: {_entryMode},
            onSelectionChanged: (selection) =>
                setState(() => _entryMode = selection.first),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<GameMode>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Modus'),
            items: [
              for (final mode in GameMode.values)
                DropdownMenuItem(
                  value: mode,
                  child: Text(gameModeLabels[mode] ?? mode.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          if (trackOtherPlayers) ...[
            const SizedBox(height: 12),
            groupsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (groups) => DropdownButtonFormField<int?>(
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: 'Gruppe'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Keine Gruppe'),
                  ),
                  for (final group in groups)
                    DropdownMenuItem<int?>(
                      value: group.id,
                      child: Text(group.name),
                    ),
                ],
                onChanged: (value) => setState(() => _groupId = value),
              ),
            ),
          ],
          if (_entryMode == GameEntryMode.manual) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Datum'),
              subtitle: Text(
                '${_playedAt.day.toString().padLeft(2, '0')}.'
                '${_playedAt.month.toString().padLeft(2, '0')}.'
                '${_playedAt.year}',
              ),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notizen (optional)',
              ),
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Teilnehmer',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Row(
                children: [
                  if (trackOtherPlayers)
                    IconButton(
                      onPressed: _addKnownParticipant,
                      icon: const Icon(Icons.person_add),
                      tooltip: 'Bekannten Spieler hinzufügen',
                    ),
                  IconButton(
                    onPressed: _addAnonymousParticipant,
                    icon: const Icon(Icons.person_add_alt),
                    tooltip: 'Unbekannten Spieler hinzufügen',
                  ),
                ],
              ),
            ],
          ),
          if (_participants.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Noch keine Teilnehmer hinzugefügt.'),
            ),
          for (var i = 0; i < _participants.length; i++)
            _ParticipantCard(
              draft: _participants[i],
              mode: _mode,
              showPlacement: _entryMode == GameEntryMode.manual && !_isTeamMode,
              isDraw: _isDraw,
              onRemove: () => _removeParticipant(i),
              onStartPositionChanged: (v) => _setStartPosition(i, v),
              onPlacementChanged: (v) => _setPlacement(i, v),
              onTeamChanged: (team) => _setTeam(i, team),
              onSetArchenemy: () => _setArchenemy(i),
              onChangeDeck:
                  _participants[i].isAnonymous ? null : () => _changeDeck(i),
            ),
          if (_entryMode == GameEntryMode.manual) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDraw,
              onChanged: (value) => _setDraw(value ?? false),
              title: const Text('Unentschieden'),
            ),
            if (!_isDraw && _mode == GameMode.twoHeadedGiant)
              _TeamWinnerSelector(onSelectTeam: _setTeamWinner),
            if (!_isDraw && _mode == GameMode.archenemy)
              _ArchenemyWinnerSelector(onSelect: _setArchenemyWinner),
          ],
          if (_entryMode == GameEntryMode.live) ...[
            const SizedBox(height: 24),
            Text(
              'Start-Lebenspunkte',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(
                    () => _startingLife = (_startingLife - 1).clamp(1, 999),
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_startingLife',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  onPressed: () => setState(
                    () => _startingLife = (_startingLife + 1).clamp(1, 999),
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tisch-Anordnung',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _autoArrangeSeats,
                  icon: const Icon(Icons.route_outlined, size: 18),
                  label: const Text('Automatisch anordnen'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Bestimmt Position und Drehung der Lebenspunkte-Kacheln in '
              'der Live-Ansicht, wenn das Gerät flach auf dem Tisch liegt. '
              'Auf einen Namen tippen, um die Seite zu ändern - oder '
              '"Automatisch anordnen" lässt die Sitzplätze passend zur '
              'Startreihenfolge im Uhrzeigersinn vorschlagen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _TableSeatPicker(
              participants: _participants,
              onChanged: _setTableSide,
              onSwap: _swapStartPositions,
            ),
          ],
          const SizedBox(height: 16),
          if (error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_entryMode == GameEntryMode.manual)
            FilledButton.icon(
              onPressed: error == null ? _saveManual : null,
              icon: const Icon(Icons.save),
              label: const Text('Manuell speichern'),
            )
          else
            FilledButton.icon(
              onPressed: error == null ? _startLive : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Live-Erfassung starten'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  final GameParticipantDraft draft;
  final GameMode mode;
  final bool showPlacement;
  final bool isDraw;
  final VoidCallback onRemove;
  final ValueChanged<int> onStartPositionChanged;
  final ValueChanged<int> onPlacementChanged;
  final ValueChanged<String> onTeamChanged;
  final VoidCallback onSetArchenemy;

  /// Öffnet die Deck-Auswahl für diesen Teilnehmer - nur für bekannte
  /// Spieler gesetzt (bei anonymen Teilnehmern gibt es kein Deck aus
  /// der Decks-Tabelle, siehe GameParticipantDraft.isAnonymous), sonst
  /// null und der Button wird nicht angezeigt.
  final VoidCallback? onChangeDeck;

  const _ParticipantCard({
    required this.draft,
    required this.mode,
    required this.showPlacement,
    required this.isDraw,
    required this.onRemove,
    required this.onStartPositionChanged,
    required this.onPlacementChanged,
    required this.onTeamChanged,
    required this.onSetArchenemy,
    required this.onChangeDeck,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              draft.deckOwnerName != null
                                  ? '${draft.deckName} (geliehen von '
                                      '${draft.deckOwnerName})'
                                  : draft.deckName ??
                                      // Noch KEIN Deck gewählt UND ein
                                      // bekannter Spieler (onChangeDeck
                                      // != null, siehe Klassendoku
                                      // oben) - statt der irreführenden
                                      // Standard-Farbidentität
                                      // "Farblos" (Nutzerwunsch: sah
                                      // wie eine bewusste Deck-Wahl
                                      // aus, war aber nur der leere
                                      // Default) ein klarer Hinweis,
                                      // dass hier noch eine Auswahl
                                      // fehlt. Bei einem ECHT
                                      // farblosen Deck steht ohnehin
                                      // der Deckname (draft.deckName)
                                      // da, nicht dieser Zweig. Bei
                                      // anonymen Teilnehmern
                                      // (onChangeDeck == null) bleibt
                                      // "Farblos" korrekt, da dort die
                                      // Farbidentität bewusst gewählt
                                      // wird (siehe
                                      // AddAnonymousParticipantDialog/
                                      // ColorIdentityPicker).
                                      (onChangeDeck != null
                                          ? 'Noch kein Deck ausgewählt'
                                          : (draft.colorIdentity.isEmpty
                                              ? 'Farblos'
                                              : draft.colorIdentity)),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (onChangeDeck != null)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: onChangeDeck,
                              icon: const Icon(Icons.style_outlined, size: 18),
                              tooltip: 'Deck ändern',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: onRemove, icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Stepper(
                  label: 'Start',
                  value: draft.startPosition,
                  onChanged: onStartPositionChanged,
                ),
                if (showPlacement && !isDraw)
                  _Stepper(
                    label: 'Platz',
                    value: draft.placement,
                    onChanged: onPlacementChanged,
                  ),
                if (mode == GameMode.twoHeadedGiant)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: const Text('Team A'),
                        selected: draft.team == 'A',
                        onSelected: (_) => onTeamChanged('A'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Team B'),
                        selected: draft.team == 'B',
                        onSelected: (_) => onTeamChanged('B'),
                      ),
                    ],
                  ),
                if (mode == GameMode.archenemy)
                  FilterChip(
                    label: const Text('Erzfeind'),
                    selected: draft.team == 'archenemy',
                    onSelected: (_) => onSetArchenemy(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: '),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged((value ?? 1) - 1),
          icon: const Icon(Icons.remove_circle_outline, size: 18),
        ),
        Text(value?.toString() ?? '-'),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged((value ?? 0) + 1),
          icon: const Icon(Icons.add_circle_outline, size: 18),
        ),
      ],
    );
  }
}

class _TeamWinnerSelector extends StatelessWidget {
  final ValueChanged<String> onSelectTeam;

  const _TeamWinnerSelector({required this.onSelectTeam});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Text('Sieger-Team:'),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => onSelectTeam('A'),
            child: const Text('Team A'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => onSelectTeam('B'),
            child: const Text('Team B'),
          ),
        ],
      ),
    );
  }
}

class _ArchenemyWinnerSelector extends StatelessWidget {
  final ValueChanged<bool> onSelect;

  const _ArchenemyWinnerSelector({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Text('Sieger:'),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => onSelect(true),
            child: const Text('Erzfeind'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => onSelect(false),
            child: const Text('Team'),
          ),
        ],
      ),
    );
  }
}

/// Visueller Sitzplatz-Wähler für die Live-Ansicht (Nutzerwunsch,
/// angelehnt an einen Referenz-Screenshot mit Tisch-Diagramm): zeigt
/// ein Tisch-Diagramm mit vier Zonen (oben/unten/links/rechts) - exakt
/// dieselbe Anordnung, in der die Lebenspunkte-Kacheln später im
/// Live-Grid erscheinen (siehe _LifeGrid in live_game_screen.dart) -
/// und ordnet jeden Teilnehmer als Chip in seiner aktuell gewählten
/// Zone ein. Tippen auf einen Chip öffnet ein Menü zum Umstellen der
/// Seite sowie (falls mind. ein weiterer Teilnehmer auf derselben
/// Seite sitzt) zum Platz-Tausch mit genau diesem (siehe onSwap).
/// Bewusst kein Drag&Drop zwischen den Zonen: in dieser
/// Cloud-Umgebung ohne echtes Flutter-Tooling (nur strukturelle
/// Klammer-Prüfung, siehe ARCHITECTURE.md) lässt sich eine
/// Drag-Geste nicht zuverlässig verifizieren - das Tippen+Menü liefert
/// dieselbe Zuordnungsmöglichkeit, nur mit einer robusteren
/// Interaktion. Teilnehmer ohne explizit gesetzte Seite gelten als
/// "unten" (siehe GameParticipantDraft.tableSide/_defaultTableSide).
class _TableSeatPicker extends StatelessWidget {
  final List<GameParticipantDraft> participants;
  final void Function(int index, TableSide side) onChanged;

  /// Tauscht die Startposition zweier Teilnehmer DERSELBEN Seite (siehe
  /// GameSetupScreen._swapStartPositions) - Nutzerwunsch: "zwei
  /// Personen, die an einer Tischseite sitzen, [sollen] miteinander die
  /// Plätze tauschen können". Wird aus dem Popup-Menü eines
  /// Sitzplatz-Chips heraus aufgerufen (siehe _seatChip).
  final void Function(int indexA, int indexB) onSwap;

  const _TableSeatPicker({
    required this.participants,
    required this.onChanged,
    required this.onSwap,
  });

  /// Indizes der Teilnehmer dieser Seite, sortiert nach Startreihenfolge
  /// in der für diese Seite geltenden Uhrzeigersinn-Richtung (siehe
  /// sortForTableSide) - unabhängig davon, in welcher Reihenfolge sie
  /// ursprünglich zur Partie hinzugefügt wurden.
  List<int> _indexesFor(TableSide side) {
    final indexes = [
      for (var i = 0; i < participants.length; i++)
        if ((participants[i].tableSide ?? TableSide.bottom) == side) i,
    ];
    return sortForTableSide(
      indexes,
      side,
      (i) => participants[i].startPosition,
    );
  }

  Widget _zone(
    BuildContext context,
    String label,
    List<int> indexes,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: indexes.isEmpty
          ? Center(
              child: Text(
                label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            )
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [for (final i in indexes) _seatChip(context, i)],
            ),
    );
  }

  Widget _seatChip(BuildContext context, int index) {
    final draft = participants[index];
    final current = draft.tableSide ?? TableSide.bottom;
    // Andere Teilnehmer derselben Seite - für den "Platz tauschen
    // mit..."-Menüteil unten (nur sinnvoll unter Teilnehmern derselben
    // Seite, siehe onSwap-Doku).
    final sameSideIndexes = [
      for (var i = 0; i < participants.length; i++)
        if (i != index &&
            (participants[i].tableSide ?? TableSide.bottom) == current)
          i,
    ];
    return PopupMenuButton<Object>(
      tooltip: 'Sitzplatz ändern',
      onSelected: (value) {
        if (value is TableSide) {
          onChanged(index, value);
        } else if (value is int) {
          onSwap(index, value);
        }
      },
      itemBuilder: (context) => [
        for (final side in TableSide.values)
          PopupMenuItem(
            value: side,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  side == current ? Icons.check : null,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(tableSideLabels[side] ?? side.name),
              ],
            ),
          ),
        if (sameSideIndexes.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final otherIndex in sameSideIndexes)
            PopupMenuItem(
              value: otherIndex,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Platz tauschen mit '
                    '${participants[otherIndex].displayName}',
                  ),
                ],
              ),
            ),
        ],
      ],
      child: Chip(label: Text(draft.displayName)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _zone(context, 'Oben', _indexesFor(TableSide.top)),
        const SizedBox(height: 6),
        // IntrinsicHeight ist hier zwingend nötig: Row +
        // CrossAxisAlignment.stretch braucht eine BEGRENZTE Höhe zum
        // Strecken, aber diese Row steht als normales (nicht in
        // Expanded gepacktes) Column-Kind innerhalb der äußeren
        // ListView des Setup-Screens - dort ist die Höhe unbegrenzt
        // (Bugreport: "kann nicht so weit runterscrollen", weil genau
        // das beim ersten Versuch ohne IntrinsicHeight zu einem
        // Layout-Fehler führte und die ListView ab hier nicht mehr
        // richtig gerendert/gescrollt werden konnte).
        // IntrinsicHeight berechnet die tatsächlich benötigte Höhe
        // der Zeile und gibt sie als feste Zwangsvorgabe an Row
        // weiter, wodurch stretch wieder funktioniert.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _zone(context, 'Links', _indexesFor(TableSide.left)),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.table_bar_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _zone(context, 'Rechts', _indexesFor(TableSide.right)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _zone(context, 'Unten', _indexesFor(TableSide.bottom)),
      ],
    );
  }
}
