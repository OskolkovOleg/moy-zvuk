import 'dart:math';

import '../data/models.dart';

class ScoreRange {
  const ScoreRange(this.min, this.max) : assert(min <= max);
  final int min, max;
}

/// Filter before randomizing. Include both boundaries and every occurrence.
List<Track> shuffledTracks(
  List<Track> source,
  Map<String, Rating> ratings, {
  int? minScore,
  int? maxScore,
  Random? random,
}) {
  if (minScore != null && maxScore != null && minScore > maxScore) {
    throw ArgumentError('Начало диапазона больше конца');
  }
  return source.where((track) {
    final score = trackScore(track.id, ratings);
    return (minScore == null || score >= minScore) &&
        (maxScore == null || score <= maxScore);
  }).toList()..shuffle(random);
}
