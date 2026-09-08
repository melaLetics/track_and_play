/// Deutsche Monatsnamen fuer die nach Jahr/Monat gruppierte
/// Partien-Uebersicht (siehe games_overview_screen.dart) - 1:1 aus
/// mtg_stats_tracker uebernommen (dort core/globals.dart,
/// monthName). Bewusst fest hinterlegt statt ueber intl/DateFormat
/// mit Locale-Initialisierung, da `intl` bislang nirgends in dieser
/// App fuer Datumsformatierung genutzt wird und so keine zusaetzliche
/// Locale-Initialisierung (initializeDateFormatting) noetig ist.
String monthNameDe(int month) {
  const months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  return months[month - 1];
}
