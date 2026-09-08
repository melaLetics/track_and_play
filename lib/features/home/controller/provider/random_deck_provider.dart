import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/app_database.dart';

/// Hält das zuletzt gewürfelte Deck der Random-Deck-Funktion (Home-
/// Dashboard). [roll] bekommt die bereits gefilterte Kandidatenliste
/// von außen übergeben (Filterung passt sich damit über
/// filterDecksForRandom() an, ohne dass dieser Notifier den Filter
/// selbst kennen muss).
class RandomDeckNotifier extends Notifier<Deck?> {
  final _random = Random();

  @override
  Deck? build() => null;

  void roll(List<Deck> candidates) {
    if (candidates.isEmpty) return;
    state = candidates[_random.nextInt(candidates.length)];
  }
}

final randomDeckProvider = NotifierProvider<RandomDeckNotifier, Deck?>(
  RandomDeckNotifier.new,
);
