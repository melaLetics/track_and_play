import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/mana_colors.dart';

/// Deck-Kachel im "Kartenstapel"-Look (Nutzerwunsch: angelehnt an die
/// alte App mtg_stats_tracker, dort als "Karten liegen uebereinander"
/// erinnert - in der alten App selbst aber nur als nie fertig gebauter
/// leerer Stack-Rest vorgefunden, siehe ARCHITECTURE.md "Bekannte
/// Fixes". Umgesetzt als rein dekorativer Stapel-Effekt (mit dem
/// Nutzer abgestimmt): zwei leicht rotierte/versetzte "Kartenruecken"
/// in den Mana-Farben des Decks (siehe mana_colors.dart) liegen hinter
/// der eigentlichen Info-Kachel, OHNE echte Magic-Kartenbilder (die
/// gibt es in dieser App nicht und wurden explizit nicht gewuenscht).
///
/// Ersetzt das bisherige einfache `ListTile` in [PlayerDetailScreen]
/// 1:1 in der Funktion (Titel/Untertitel/Trailing/Tap sowie das
/// Abdunkeln archivierter Decks via [archived]), nur optisch
/// aufbereitet.
///
/// [link] (Nutzerwunsch): optionale dritte Zeile unter [subtitle] -
/// nur sichtbar, wenn ein Deck-Link hinterlegt ist (siehe
/// Decks.deckLink/DeckFormDialog). Eigener Tap-Bereich (siehe
/// [_openLink]), unabhängig vom card-weiten [onTap] (der weiterhin
/// den Bearbeiten-Dialog öffnet) - funktioniert wie ein Trailing-
/// Icon-Button innerhalb derselben Karte, siehe [trailing].
class DeckStackCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? link;
  final String colorIdentity;
  final bool archived;
  final Widget? trailing;
  final VoidCallback? onTap;

  const DeckStackCard({
    super.key,
    required this.name,
    this.subtitle,
    this.link,
    required this.colorIdentity,
    this.archived = false,
    this.trailing,
    this.onTap,
  });

  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = manaColorsFor(colorIdentity);

    Widget backLayer({
      required double rotationDeg,
      required Offset offset,
      required double opacity,
    }) {
      return Positioned.fill(
        child: Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: rotationDeg * math.pi / 180,
            child: Opacity(
              opacity: opacity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: colors.length == 1
                      ? LinearGradient(
                          colors: [
                            colors.first.withValues(alpha: .85),
                            colors.first,
                          ],
                        )
                      : LinearGradient(
                          colors: colors,
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .35),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final accentStripe = Container(
      width: 6,
      decoration: BoxDecoration(
        color: colors.length == 1 ? colors.first : null,
        gradient: colors.length == 1
            ? null
            : LinearGradient(
                colors: colors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
      ),
    );

    final content = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    accentStripe,
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (subtitle != null &&
                                      subtitle!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurface
                                                .withValues(alpha: .7),
                                          ),
                                    ),
                                  ],
                                  if (link != null && link!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    InkWell(
                                      onTap: () => _openLink(context, link!),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.link,
                                            size: 14,
                                            color: scheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              link!,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: scheme.primary,
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (trailing != null) trailing!,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: archived ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            backLayer(
              rotationDeg: -4,
              offset: const Offset(-4, 6),
              opacity: .55,
            ),
            backLayer(
              rotationDeg: 3,
              offset: const Offset(4, 3),
              opacity: .75,
            ),
            content,
          ],
        ),
      ),
    );
  }

  /// Öffnet [rawLink] im externen Browser (Nutzerwunsch: Deck-Link
  /// muss tatsächlich funktionieren, nicht nur angezeigt werden).
  /// Ergänzt bei Bedarf `https://` (Nutzer geben Links oft ohne
  /// Schema ein, z. B. "moxfield.com/decks/..." statt
  /// "https://moxfield.com/decks/..." - `Uri.parse` allein würde das
  /// sonst als relativen Pfad ohne Host interpretieren und
  /// `launchUrl` schlaegt fehl). `messenger` wird bewusst VOR dem
  /// `await` geholt (nicht danach per `context` erneut), damit kein
  /// möglicherweise nicht mehr gemountetes `BuildContext` nach der
  /// asynchronen Lücke verwendet wird.
  Future<void> _openLink(BuildContext context, String rawLink) async {
    final trimmed = rawLink.trim();
    if (trimmed.isEmpty) return;
    final hasScheme = Uri.tryParse(trimmed)?.hasScheme ?? false;
    final uri = Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
    final messenger = ScaffoldMessenger.of(context);
    if (uri == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ungültiger Deck-Link.')),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        SnackBar(content: Text('Konnte Link nicht öffnen: $trimmed')),
      );
    }
  }
}
