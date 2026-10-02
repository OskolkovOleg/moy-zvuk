import 'dart:math';

import '../data/models.dart';

/// Select before shuffling so low-scoring tracks cannot displace the top N.
/// Each occurrence appears once; a playlist may already contain duplicates.
List<Track> shuffledTracks(
  List<Track> source,
  Map<String, Rating> ratings, {
  int? bestCount,
  Random? random,
}) {
  if (bestCount != null && bestCount < 1) {
    throw ArgumentError.value(bestCount, 'bestCount', 'Must be positive');
  }
  final selected = bestCount == null
      ? List<Track>.of(source)
      : rankedTracks(source, ratings).take(bestCount).toList();
  return selected..shuffle(random);
}
