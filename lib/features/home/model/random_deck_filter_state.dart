import '../../../database/app_database.dart';

/// Filter-Kriterien für die Random-Deck-Funktion (Home-Dashboard) -
/// 1:1 aus mtg_stats_tracker übernommen (RandomDeckFilterState/
/// TypeFilter/ProxyFilter), da das Deck-Modell hier dieselben Felder
/// hat (bracket/buildType/isProxy, siehe deck_form_dialog.dart).
enum TypeFilter { all, precon, upgraded, homebrew }

enum ProxyFilter { all, proxyOnly, originalOnly }

class RandomDeckFilterState {
  final int? bracket;
  final TypeFilter type;
  final ProxyFilter proxy;

  const RandomDeckFilterState({
    this.bracket,
    this.type = TypeFilter.all,
    this.proxy = ProxyFilter.all,
  });

  bool get hasActiveFilters =>
      bracket != null || type != TypeFilter.all || proxy != ProxyFilter.all;
}

/// Wendet [filter] auf [decks] an. Reine Funktion (kein DB-Zugriff),
/// analog zu den anderen Berechnungs-Funktionen im Projekt (z. B.
/// achievement_engine.dart).
List<Deck> filterDecksForRandom(List<Deck> decks, RandomDeckFilterState filter) {
  return decks.where((deck) {
    if (filter.bracket != null && deck.bracket != filter.bracket) {
      return false;
    }
    if (filter.type != TypeFilter.all) {
      final wanted = switch (filter.type) {
        TypeFilter.precon => DeckBuildType.precon,
        TypeFilter.upgraded => DeckBuildType.upgraded,
        TypeFilter.homebrew => DeckBuildType.homebrew,
        TypeFilter.all => null,
      };
      if (deck.buildType != wanted) return false;
    }
    if (filter.proxy == ProxyFilter.proxyOnly && !deck.isProxy) {
      return false;
    }
    if (filter.proxy == ProxyFilter.originalOnly && deck.isProxy) {
      return false;
    }
    return true;
  }).toList();
}
