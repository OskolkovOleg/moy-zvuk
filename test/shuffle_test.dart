import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/shuffle_tracks.dart';

void main() {
  const a = Track(id: 'a', title: 'A'),
      b = Track(id: 'b', title: 'B'),
      c = Track(id: 'c', title: 'C');
  test(
    'Inclusive score range is selected before shuffling, including defaults',
    () {
      final source = [a, b, c];
      final ratings = {'a': const Rating(-2, 11), 'c': const Rating(18, 9)};
      for (var seed = 0; seed < 12; seed++) {
        expect(
          shuffledTracks(
            source,
            ratings,
            minScore: -2,
            maxScore: 9,
            random: Random(seed),
          ),
          unorderedEquals([a, b]),
        );
      }
      expect(shuffledTracks(source, ratings, minScore: 18, maxScore: 18), [c]);
      expect(
        shuffledTracks(source, ratings, minScore: 10, maxScore: 17),
        isEmpty,
      );
      expect(source, [a, b, c]);
    },
  );
  test('Shuffle preserves occurrences and leaves source untouched', () {
    final source = [a, b, a, c], orders = <String>{};
    for (var seed = 0; seed < 12; seed++) {
      final result = shuffledTracks(source, {}, random: Random(seed));
      expect(result, unorderedEquals(source));
      orders.add(result.map((t) => t.id).join());
    }
    expect(orders.length, greaterThan(1));
    expect(source, [a, b, a, c]);
    expect(
      shuffledTracks(source, {}, minScore: 9, maxScore: 9),
      unorderedEquals(source),
    );
  });
  test('Empty, equal scores, one-sided ranges and reversed ranges', () {
    expect(shuffledTracks([], {}, minScore: 0, maxScore: 0), isEmpty);
    expect(shuffledTracks([a], {}, minScore: 9), [a]);
    expect(shuffledTracks([a], {}, maxScore: 8), isEmpty);
    expect(
      () => shuffledTracks([a], {}, minScore: 10, maxScore: 9),
      throwsArgumentError,
    );
  });
}
