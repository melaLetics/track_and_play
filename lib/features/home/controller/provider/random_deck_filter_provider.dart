import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/random_deck_filter_state.dart';

/// Hält den aktuellen Filter für die Random-Deck-Funktion (siehe
/// random_deck_filter_state.dart). Bewusst mit expliziten Setter-
/// Methoden statt copyWith(int? bracket) - ein nullable copyWith-
/// Parameter kann "nicht ändern" und "auf null setzen" nicht sauber
/// unterscheiden, siehe ARCHITECTURE.md.
class RandomDeckFilterNotifier extends Notifier<RandomDeckFilterState> {
  @override
  RandomDeckFilterState build() => const RandomDeckFilterState();

  void setBracket(int? bracket) {
    state = RandomDeckFilterState(
      bracket: bracket,
      type: state.type,
      proxy: state.proxy,
    );
  }

  void setTypeFilter(TypeFilter type) {
    state = RandomDeckFilterState(
      bracket: state.bracket,
      type: type,
      proxy: state.proxy,
    );
  }

  void setProxyFilter(ProxyFilter proxy) {
    state = RandomDeckFilterState(
      bracket: state.bracket,
      type: state.type,
      proxy: proxy,
    );
  }

  void reset() {
    state = const RandomDeckFilterState();
  }
}

final randomDeckFilterProvider =
    NotifierProvider<RandomDeckFilterNotifier, RandomDeckFilterState>(
  RandomDeckFilterNotifier.new,
);
