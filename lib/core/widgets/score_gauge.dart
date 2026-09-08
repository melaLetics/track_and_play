import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rundes "Barometer" für einen 0-100-Score, mit Zahl + Label in der
/// Mitte - Geometrie 1:1 aus dem "Speedometer" von mtg_stats_tracker
/// übernommen (270°-Bogen von 135° bis 405°, Ticks alle 2 Einheiten,
/// Marker-Punkt am aktuellen Wert). Farben kommen bewusst aus dem
/// App-Theme statt hartcodiertem Weiß wie im Original, damit die
/// Komponente auch im (aktuell ungenutzten) hellen Modus von
/// "Vault & Foil" funktionieren würde, siehe app_theme.dart.
class ScoreGauge extends StatelessWidget {
  final int score;
  final String label;
  final double size;

  const ScoreGauge({
    required this.score,
    required this.label,
    this.size = 200,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: CustomPaint(
          painter: _ScoreGaugePainter(
            value: score.clamp(0, 100),
            trackColor: scheme.outlineVariant,
            valueColor: scheme.primary,
            tickColor: scheme.outlineVariant,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score.toString(),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreGaugePainter extends CustomPainter {
  final int value;
  final Color trackColor;
  final Color valueColor;
  final Color tickColor;

  const _ScoreGaugePainter({
    required this.value,
    required this.trackColor,
    required this.valueColor,
    required this.tickColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    const startAngle = 3 / 4 * math.pi;
    const sweepAngle = 3 / 2 * math.pi;

    final backgroundRing = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;

    final valueRing = Paint()
      ..color = valueColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 20),
      startAngle,
      sweepAngle,
      false,
      backgroundRing,
    );

    final valueSweep = sweepAngle * (value / 100);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 20),
      startAngle,
      valueSweep,
      false,
      valueRing,
    );

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 2;

    for (var i = 0; i <= 100; i += 2) {
      final angle = startAngle + sweepAngle * (i / 100);
      final outer = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - 8),
        center.dy + math.sin(angle) * (radius - 8),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    final markerAngle = startAngle + valueSweep;
    final markerCenter = Offset(
      center.dx + math.cos(markerAngle) * (radius - 20),
      center.dy + math.sin(markerAngle) * (radius - 20),
    );
    canvas.drawCircle(markerCenter, 6, Paint()..color = valueColor);
  }

  @override
  bool shouldRepaint(covariant _ScoreGaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor ||
        oldDelegate.tickColor != tickColor;
  }
}
