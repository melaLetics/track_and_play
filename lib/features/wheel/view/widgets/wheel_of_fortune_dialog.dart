import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/color_identity_utils.dart';
import '../../../../core/utils/mana_colors.dart';
import '../../../../core/widgets/mana_symbol.dart';
import '../../../settings/controller/provider/app_settings_provider.dart';
import '../screen/wheel_tasks_screen.dart';
import 'wheel_result_overlay.dart';

/// Overlay-Dialog fürs optionale Wheel-of-Fortune-Gamification-Feature
/// (Nutzerwunsch) - 10 Felder, jede der 5 WUBRG-Farben zweimal (siehe
/// [_segments]), aufgerufen über den "Rad drehen"-Button in
/// LiveGameScreen (nur sichtbar, wenn AppSettings.wheelOfFortuneEnabled
/// gesetzt ist - siehe dort). Das Drehen selbst ist reine Optik/Zufall
/// (kein Bezug zur eigentlichen Partie-Datenbank) - nach dem
/// Stillstand wird die für die aktuelle Eskalations-Stufe in
/// AppSettings.wheelTasks/wheelTasksStage2/.../wheelTasksStage5
/// hinterlegte Aufgabe der getroffenen Farbe in einem eigenen,
/// prominenten Overlay angezeigt (siehe [_showResultOverlay]/
/// WheelResultOverlay - Nutzer-Feedback: das bisherige Inline-Ergebnis
/// unter dem Rad war zu unauffällig); die Spieler setzen die Aufgabe
/// selbst manuell am Tisch um (z. B. über die normalen
/// Lebenspunkte-Zähler).
///
/// **Eskalations-Stufen** (Nutzerwunsch: ursprünglich "drei
/// Eskalations-Stufen ... eine neue Stufe ist erreicht, wenn das Rad so
/// oft gedreht wurde, wie Mitspieler teilnehmen", später auf
/// "insgesamt fünf Eskalationsstufen" erweitert): siehe
/// [_stageForSpinNumber] für die genaue Berechnung - Stufe 1 gilt für
/// die ersten [participantCount] Drehungen dieser Partie, jede weitere
/// Stufe für die jeweils nächsten [participantCount] Drehungen, ab
/// Stufe [_maxStage] (nach insgesamt (_maxStage-1)x[participantCount]
/// Drehungen) bleiben die Aufgaben unabhängig von weiteren Drehungen
/// gleich (Maximum).
class WheelOfFortuneDialog extends ConsumerStatefulWidget {
  /// Anzahl der Teilnehmer der aktuellen Partie (inkl. man selbst) -
  /// bestimmt zusammen mit [spinsCompleted] die aktuelle
  /// Eskalations-Stufe (siehe _WheelOfFortuneDialogState._stageForSpinNumber:
  /// eine neue Stufe wird erreicht, sobald so oft gedreht wurde, wie
  /// Mitspieler teilnehmen - Nutzerwunsch).
  final int participantCount;

  /// Anzahl der in dieser Partie VOR dem Öffnen dieses Dialogs bereits
  /// erfolgten Drehungen (über LiveGameScreen persistiert, da der
  /// Dialog selbst bei jedem Öffnen neu erzeugt wird und sein eigener
  /// State somit beim Schließen verloren ginge).
  final int spinsCompleted;

  /// Wird nach jeder abgeschlossenen Drehung aufgerufen, damit
  /// LiveGameScreen seinen Zähler fortschreibt (siehe [spinsCompleted]).
  final VoidCallback onSpinCompleted;

  const WheelOfFortuneDialog({
    super.key,
    required this.participantCount,
    required this.spinsCompleted,
    required this.onSpinCompleted,
  });

  @override
  ConsumerState<WheelOfFortuneDialog> createState() =>
      _WheelOfFortuneDialogState();
}

class _WheelOfFortuneDialogState extends ConsumerState<WheelOfFortuneDialog>
    with SingleTickerProviderStateMixin {
  /// Feste Reihenfolge der 10 Rad-Felder: jede WUBRG-Farbe zweimal,
  /// interleaved (nicht geblockt) - dadurch liegen die beiden Felder
  /// derselben Farbe einander exakt gegenüber (5 von 10 Feldern
  /// auseinander), was das Rad optisch ausgewogen wirken lässt.
  static final List<String> _segments = [...wubrgOrder, ...wubrgOrder];

  late final AnimationController _controller;
  late Animation<double> _rotationAnimation;

  /// Aktuelle Ruhe-Rotation des Rads (Bogenmaß) - wächst über mehrere
  /// Drehungen hinweg monoton, damit das Rad beim nächsten Drehen
  /// nicht sichtbar auf 0 zurückspringt, sondern von seiner aktuellen
  /// Position aus weiterdreht.
  double _restRotation = 0;
  bool _spinning = false;
  String? _resultColor;

  /// Anzahl der Eskalations-Stufen insgesamt (Nutzerwunsch: "auf
  /// insgesamt fünf Eskalationsstufen erweitern") - siehe
  /// _stageForSpinNumber/AppSettings.wheelTasksForStage.
  static const _maxStage = 5;

  /// Laufender Drehungs-Zähler dieser Partie, initialisiert aus
  /// widget.spinsCompleted (Stand vor dem Öffnen) und lokal
  /// weitergezählt, damit auch mehrfaches "Nochmal drehen" INNERHALB
  /// desselben Dialog-Aufrufs die Eskalations-Stufe korrekt weiterschaltet.
  late int _spinsCompleted = widget.spinsCompleted;

  int get _participantCountSafe =>
      widget.participantCount < 1 ? 1 : widget.participantCount;

  /// Eskalations-Stufe (1-[_maxStage]) für die [spinNumber]-te Drehung
  /// dieser Partie (1-indiziert). Stufe N beginnt bei Drehung
  /// (N-1) x [_participantCountSafe] + 1 - danach bleibt es bei Stufe
  /// [_maxStage] (Maximum), egal wie oft noch gedreht wird
  /// (Nutzerwunsch).
  int _stageForSpinNumber(int spinNumber) {
    final stageIndex = ((spinNumber - 1) ~/ _participantCountSafe)
        .clamp(0, _maxStage - 1);
    return stageIndex + 1;
  }

  /// Stufe, die die NÄCHSTE Drehung auslösen würde - für die
  /// Stufen-Anzeige im Dialog (build()).
  int get _nextStage => _stageForSpinNumber(_spinsCompleted + 1);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_spinning) return;
    final random = math.Random();
    final targetIndex = random.nextInt(_segments.length);
    final sliceAngle = 2 * math.pi / _segments.length;
    const twoPi = 2 * math.pi;

    // Zielrotation, bei der Segment [targetIndex] am (fest oben
    // positionierten) Zeiger zum Stillstand kommt - siehe
    // _buildWheel/_WheelSlicesPainter für die zugrunde liegende
    // Winkel-Konvention (Segment i zentriert bei -pi/2 + i*sliceAngle
    // im unrotierten Rad).
    final targetRestRotation = -targetIndex * sliceAngle;
    var delta = (targetRestRotation - _restRotation) % twoPi;
    if (delta < 0) delta += twoPi;
    final fullSpins = 5 + random.nextInt(3);
    final newRotation = _restRotation + delta + twoPi * fullSpins;

    setState(() {
      _spinning = true;
      _resultColor = null;
    });

    _rotationAnimation = Tween<double>(
      begin: _restRotation,
      end: newRotation,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.reset();
    await _controller.forward();
    if (!mounted) return;

    final resultColor = _segments[targetIndex];
    // Stufe VOR dem Hochzählen berechnen - _spinsCompleted zu diesem
    // Zeitpunkt zählt die Drehungen VOR der aktuellen, die gerade
    // resolved wird (siehe _stageForSpinNumber).
    final stage = _stageForSpinNumber(_spinsCompleted + 1);

    setState(() {
      _spinning = false;
      _restRotation = newRotation;
      _resultColor = resultColor;
      _spinsCompleted++;
    });
    widget.onSpinCompleted();

    final wheelTasks = ref.read(settingsControllerProvider).maybeWhen(
          data: (settings) => settings.wheelTasksForStage(stage),
          orElse: () => const <String, String>{},
        );
    final taskText = wheelTasks[resultColor] ?? '(keine Aufgabe hinterlegt)';
    await _showResultOverlay(resultColor, taskText, stage);
  }

  /// Zeigt das Drehergebnis prominent in einem eigenen Overlay
  /// (siehe WheelResultOverlay) OBEN AUF diesem Dialog - mit einer
  /// Skalier-/Einblend-Animation statt der Standard-Dialog-Transition,
  /// damit es bewusst wie eine kleine "Preis-Enthüllung" wirkt
  /// (Nutzer-Feedback: das bisherige Inline-Ergebnis "gefällt nicht").
  Future<void> _showResultOverlay(String color, String taskText, int stage) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Ergebnis schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) {
        return WheelResultOverlay(color: color, taskText: taskText, stage: stage);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
  }

  void _openTaskManagement() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WheelTasksScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const wheelSize = 220.0;

    // Rad und Bedien-Buttons NEBENEINANDER (Row) statt untereinander -
    // Nutzer-Feedback: LiveGameScreen ist landscape-gesperrt, im
    // vorherigen vertikalen Layout mussten die Buttons unterhalb des
    // Rads durch Scrollen erreicht werden. Die äußere horizontale
    // Scrollansicht bleibt nur als Sicherheitsnetz für sehr schmale
    // Bildschirme - im Normalfall ist kein Scrollen mehr nötig.
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildWheel(wheelSize),
              const SizedBox(width: 28),
              SizedBox(
                width: 180,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Wheel of Fortune',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Aufgaben verwalten',
                          onPressed: _spinning ? null : _openTaskManagement,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stufe $_nextStage von $_maxStage',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _spinning ? null : _spin,
                      icon: const Icon(Icons.casino),
                      label: Text(
                        _spinning
                            ? 'Dreht…'
                            : (_resultColor == null ? 'Drehen' : 'Nochmal drehen'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed:
                          _spinning ? null : () => Navigator.of(context).pop(),
                      child: const Text('Schließen'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWheel(double size) {
    return SizedBox(
      width: size,
      height: size + 24,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 24,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotationAnimation.value,
                  child: child,
                );
              },
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(size, size),
                      painter: _WheelSlicesPainter(_segments),
                    ),
                    for (var i = 0; i < _segments.length; i++)
                      _buildSegmentIcon(i, size),
                    Container(
                      width: size * 0.12,
                      height: size * 0.12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: Colors.black26, width: 2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            top: 0,
            child: Icon(
              Icons.arrow_drop_down,
              size: 36,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentIcon(int index, double wheelSize) {
    final sliceAngle = 2 * math.pi / _segments.length;
    final angle = -math.pi / 2 + index * sliceAngle;
    final r = wheelSize / 2 * 0.68;
    final dx = math.cos(angle) * r;
    final dy = math.sin(angle) * r;
    return Positioned(
      left: wheelSize / 2 + dx - 14,
      top: wheelSize / 2 + dy - 14,
      child: ManaSymbol(color: _segments[index], size: 28),
    );
  }
}

/// Zeichnet die 10 farbigen Kreissegmente des Rads (siehe
/// [_WheelOfFortuneDialogState._segments]) - Segment i zentriert bei
/// Canvas-Winkel `-pi/2 + i*sliceAngle` (0 = oben, im Uhrzeigersinn),
/// passend zur Zielrotations-Berechnung in
/// [_WheelOfFortuneDialogState._spin].
class _WheelSlicesPainter extends CustomPainter {
  final List<String> segments;

  const _WheelSlicesPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final sliceAngle = 2 * math.pi / segments.length;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < segments.length; i++) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = manaColors[segments[i]] ?? colorlessManaColor;
      final startAngle = -math.pi / 2 - sliceAngle / 2 + i * sliceAngle;
      canvas.drawArc(rect, startAngle, sliceAngle, true, paint);
    }

    final dividerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x33000000);
    for (var i = 0; i < segments.length; i++) {
      final angle = -math.pi / 2 - sliceAngle / 2 + i * sliceAngle;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        dividerPaint,
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black26,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelSlicesPainter oldDelegate) =>
      oldDelegate.segments != segments;
}
