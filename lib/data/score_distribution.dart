import 'dart:collection';

import 'models.dart';

class ScoreBand {
  const ScoreBand(this.low, this.high, this.count);
  final int low, high, count;
  bool contains(int score) => score >= low && score <= high;
  String get axisLabel => low == high
      ? displayScore(low)
      : '${displayScore(low)}–${displayScore(high)}';
  String get label => low == high
      ? '$axisLabel ${_plural(low, 'балл', 'балла', 'баллов')}'
      : '$axisLabel баллов';
}

class ScoreDistribution {
  ScoreDistribution._(Map<int, int> counts)
    : counts = UnmodifiableMapView(counts),
      total = counts.values.fold(0, (sum, count) => sum + count);

  factory ScoreDistribution.fromTracks(
    Iterable<Track> tracks,
    Map<String, Rating> ratings,
  ) {
    final seen = <String>{}, counts = SplayTreeMap<int, int>();
    for (final track in tracks) {
      if (!seen.add(track.id)) continue;
      final score = trackScore(track.id, ratings);
      counts[score] = (counts[score] ?? 0) + 1;
    }
    return ScoreDistribution._(counts);
  }

  final Map<int, int> counts;
  final int total;

  // Keep every integer and its empty gaps for ordinary scores. Very wide
  // ranges use bounded, labelled intervals instead of allocating huge lists.
  List<ScoreBand> bands({int maxBands = 20}) {
    if (maxBands < 2) throw ArgumentError.value(maxBands, 'maxBands');
    if (counts.isEmpty) return const [];
    final min = counts.keys.first, max = counts.keys.last;
    final needed = (max - min + 1 + maxBands - 1) ~/ maxBands;
    var magnitude = 1;
    while (magnitude * 10 < needed) {
      magnitude *= 10;
    }
    final width = [
      1,
      2,
      5,
      10,
    ].map((value) => value * magnitude).firstWhere((value) => value >= needed);
    final size = (max - min) ~/ width + 1;
    final totals = List<int>.filled(size, 0);
    for (final entry in counts.entries) {
      totals[(entry.key - min) ~/ width] += entry.value;
    }
    return [
      for (var i = 0; i < totals.length; i++)
        ScoreBand(
          min + i * width,
          i == totals.length - 1 ? max : min + (i + 1) * width - 1,
          totals[i],
        ),
    ];
  }

  String shareLabel(int count) {
    if (total == 0 || count == 0) return '0%';
    if (count == total) return '100%';
    final value = count * 100 / total;
    return value < .1
        ? '<0,1%'
        : '${value.toStringAsFixed(1).replaceAll('.', ',')}%';
  }
}

String displayScore(int score) => score.toString().replaceFirst('-', '−');

String songCountLabel(int count) =>
    '$count ${_plural(count, 'песня', 'песни', 'песен')}';

String _plural(int count, String one, String few, String many) {
  final n = count.abs();
  if (n % 100 >= 11 && n % 100 <= 14) return many;
  return switch (n % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}
