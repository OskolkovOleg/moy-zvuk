import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/shuffle_tracks.dart';

void main() {
  const a = Track(id: 'a', title: 'A'),
      b = Track(id: 'b', title: 'B'),
      c = Track(id: 'c', title: 'C');
  test('Top N is selected by descending score before randomization', () {
    final source = [a, b, c];
    final ratings = {'a': const Rating(7, 3), 'c': const Rating(18, 8)};
    for (var seed = 0; seed < 12; seed++) {
      final result = shuffledTracks(
        source,
        ratings,
        bestCount: 2,
        random: Random(seed),
      );
      expect(result.map((t) => t.id), unorderedEquals(['b', 'c']));
    }
    expect(source, [a, b, c]);
    expect(shuffledTracks(source, ratings, bestCount: 1).single, c);
  });
  test(
    'All-track shuffle preserves occurrences and leaves source untouched',
    () {
      final source = [a, b, a, c];
      final orders = <String>{};
      for (var seed = 0; seed < 12; seed++) {
        final result = shuffledTracks(source, {}, random: Random(seed));
        expect(result, unorderedEquals(source));
        orders.add(result.map((t) => t.id).join());
      }
      expect(orders.length, greaterThan(1));
      expect(source, [a, b, a, c]);
    },
  );
  test('Ties stay stable at cutoff, limits and empty lists are safe', () {
    expect(
      shuffledTracks([a, b, c], {}, bestCount: 2),
      unorderedEquals([a, b]),
    );
    expect(shuffledTracks([a], {}, bestCount: 50), [a]);
    expect(shuffledTracks([], {}, bestCount: 1), isEmpty);
    expect(() => shuffledTracks([a], {}, bestCount: 0), throwsArgumentError);
  });
}
