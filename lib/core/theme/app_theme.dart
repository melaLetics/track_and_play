import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Vault & Foil" - das mit dem Nutzer abgestimmte App-Theme (siehe
/// ARCHITECTURE.md, Abschnitt "Bekannte Fixes"). Greift die Farbwelt des
/// App-Icons auf: ein dunkles Tresor-Petrol als Grundfarbe (statt eines
/// generischen Schwarz) und das geprägte Gold des "TAP"-Schriftzugs als
/// einzige Akzentfarbe - im hellen Modus wird aus Weiß ein warmes
/// Kartenpapier-Creme statt eines sterilen Weißtons.
///
/// Aufbau je Modus: [ColorScheme.fromSeed] liefert ein vollständiges,
/// garantiert gültiges Material-3-Schema (deckt alle Rollen inkl.
/// Container-/Outline-/Inverse-Töne ab), das anschließend per
/// `copyWith` auf die konkreten Marken-Farbwerte "getrimmt" wird - nur
/// die tatsächlich entworfenen Rollen (primary/secondary/tertiary/
/// surface/outline/error) werden fest vorgegeben, der Rest bleibt vom
/// Seed harmonisiert. Das ist robuster als ein komplett von Hand
/// befülltes [ColorScheme], da hier keine echte Analyzer-Prüfung
/// möglich ist (siehe device_bash-Einschränkung) und `fromSeed` nie an
/// einem fehlenden Pflichtfeld scheitern kann.
///
/// Typografie: Cinzel (geprägte Display-Schrift, angelehnt an den
/// "TAP"-Schriftzug) für Display-/Headline-Rollen sowie `titleLarge`
/// (davon erbt u. a. die App-Bar-Titelzeile automatisch), Manrope für
/// den Rest (Fließtext, Listen-Titel, Buttons, Labels). Für Kennzahlen
/// (Elo-Score, Lebenspunkte, Siegquote) steht zusätzlich
/// [AppTheme.statNumberStyle] mit IBM Plex Mono bereit - bewusst NICHT
/// automatisch in bestehende Screens (StatsScreen, LiveGameScreen o. Ä.)
/// eingebaut, das ist Teil der vom Nutzer ausdrücklich ans Ende
/// verschobenen "Optischen Aufbereitung der Statistik-Anzeige" (siehe
/// "Noch zu bauen", Punkt 3).
class AppTheme {
  AppTheme._();

  // --- Foil (Gold-Akzent, in beiden Modi dieselbe Familie) ---
  static const _foil = Color(0xFFD9A441);
  static const _foilBright = Color(0xFFF4CD73);
  static const _foilInk = Color(0xFF1B140A);

  // --- Vault (dunkles Tresor-Petrol) ---
  static const _vault = Color(0xFF0B1E26);
  static const _vaultSurface = Color(0xFF123340);
  static const _vaultInk = Color(0xFF163642);
  static const _tealAccentDark = Color(0xFF6FA9B8);
  static const _textOnDark = Color(0xFFEDE6D6);
  static const _borderDark = Color(0xFF274048);

  // --- Parchment (helles Kartenpapier-Creme) ---
  static const _parchment = Color(0xFFF6EFDD);
  static const _parchmentSurface = Color(0xFFEDE1C4);
  static const _textOnLight = Color(0xFF241C10);
  static const _borderLight = Color(0xFFDFCE9E);

  // --- Status (bewusst getrennt vom Gold-Akzent) ---
  static const _successLight = Color(0xFF3F7D53);
  static const _successDark = Color(0xFF6FBE8F);
  static const _errorLight = Color(0xFFA23E3E);
  static const _errorDark = Color(0xFFE0857D);

  static ColorScheme get _lightScheme {
    return ColorScheme.fromSeed(
      seedColor: _foil,
      brightness: Brightness.light,
    ).copyWith(
      primary: _foil,
      onPrimary: _foilInk,
      secondary: _vaultInk,
      onSecondary: _parchment,
      tertiary: _successLight,
      onTertiary: _parchment,
      surface: _parchment,
      onSurface: _textOnLight,
      surfaceContainerLowest: _parchment,
      surfaceContainerLow: _parchment,
      surfaceContainer: _parchmentSurface,
      surfaceContainerHigh: _parchmentSurface,
      surfaceContainerHighest: _parchmentSurface,
      outline: _borderLight,
      outlineVariant: _borderLight,
      error: _errorLight,
      onError: _parchment,
    );
  }

  static ColorScheme get _darkScheme {
    return ColorScheme.fromSeed(
      seedColor: _foilBright,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _foilBright,
      onPrimary: _foilInk,
      secondary: _tealAccentDark,
      onSecondary: _vault,
      tertiary: _successDark,
      onTertiary: _vault,
      surface: _vault,
      onSurface: _textOnDark,
      surfaceContainerLowest: _vault,
      surfaceContainerLow: _vault,
      surfaceContainer: _vaultSurface,
      surfaceContainerHigh: _vaultSurface,
      surfaceContainerHighest: _vaultSurface,
      outline: _borderDark,
      outlineVariant: _borderDark,
      error: _errorDark,
      onError: _vault,
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    final manrope = GoogleFonts.manropeTextTheme(base);
    return manrope.copyWith(
      displayLarge: GoogleFonts.cinzel(textStyle: manrope.displayLarge),
      displayMedium: GoogleFonts.cinzel(textStyle: manrope.displayMedium),
      displaySmall: GoogleFonts.cinzel(textStyle: manrope.displaySmall),
      headlineLarge: GoogleFonts.cinzel(textStyle: manrope.headlineLarge),
      headlineMedium: GoogleFonts.cinzel(textStyle: manrope.headlineMedium),
      headlineSmall: GoogleFonts.cinzel(textStyle: manrope.headlineSmall),
      // titleLarge treibt u. a. die Standard-App-Bar-Titelzeile (M3) -
      // damit bekommen alle Screens den Cinzel-Titel automatisch, ohne
      // dass jede App-Bar einzeln angefasst werden muss.
      titleLarge: GoogleFonts.cinzel(textStyle: manrope.titleLarge),
    );
  }

  static ThemeData get light => _build(_lightScheme);

  static ThemeData get dark => _build(_darkScheme);

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = _textTheme(base.textTheme);
    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        // Icons (Zurück-Pfeil, Aktionen) bleiben in der normalen
        // Textfarbe - nur die Titelzeile selbst wird unten separat auf
        // Gold gesetzt, damit nicht plötzlich auch jedes App-Bar-Icon
        // golden wird.
        foregroundColor: scheme.onSurface,
        // Screen-Überschriften (auf Nutzerwunsch): app-weit golden,
        // nicht nur der Home-Header. `textTheme.titleLarge` ist bereits
        // die Cinzel-Variante (siehe _textTheme) - hier nur die Farbe
        // überschrieben. Ein einziger Ort statt jede AppBar einzeln
        // anzufassen; Screens ohne eigenen `style:` auf ihrem
        // `title`-Text (aktuell alle) erben das automatisch.
        // fontSize explizit auf 30 gesetzt (Nutzer-Feedback: die
        // Standardgröße von titleLarge (~22) wirkte in allen
        // Screen-Headern zu klein). Gilt jetzt app-weit für jeden
        // AppBar-Titel, siehe ARCHITECTURE.md "Bekannte Fixes".
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.primary,
          fontSize: 30,
        ),
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: scheme.primary,
      ),
    );
  }

  /// Für Kennzahlen (Elo-Score, Lebenspunkte, Siegquote) - IBM Plex Mono
  /// mit tabellarischen Ziffern, damit Zahlenspalten sauber
  /// untereinanderstehen. Nutzt standardmäßig die Akzentfarbe
  /// (`colorScheme.primary`, Foil) - siehe Klassendoku für den
  /// Verwendungs-Hinweis.
  static TextStyle statNumberStyle(
    BuildContext context, {
    double fontSize = 34,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
  }) {
    return GoogleFonts.ibmPlexMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color ?? Theme.of(context).colorScheme.primary,
    );
  }
}
