import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/score_distribution.dart';

void main() {
  const a = Track(id: 'a', title: 'A'),
      b = Track(id: 'b', title: 'B'),
      c = Track(id: 'c', title: 'C');
  test(
    'Counts unique library membership, real scores, defaults and negatives',
    () {
      final ratings = {
        'a': const Rating(12, 0, frozen: true),
        'b': const Rating(-1, 20),
        'outside': const Rating(99, 90),
      };
      final distribution = ScoreDistribution.fromTracks([a, b, a, c], ratings);
      expect(distribution.total, 3);
      expect(distribution.counts, {-1: 1, 9: 1, 12: 1});
      expect(distribution.bands(), hasLength(14));
      expect(distribution.bands().first.label, '−1 балл');
      expect(distribution.bands().singleWhere((b) => b.low == 0).count, 0);
      expect(distribution.shareLabel(1), '33,3%');
      expect(distribution.shareLabel(0), '0%');
      expect(ratings['a']!.score, 12);
    },
  );
  test(
    'Empty library does not turn unrelated ratings into library statistics',
    () {
      final distribution = ScoreDistribution.fromTracks([], {
        'outside': const Rating(10, 1),
      });
      expect(distribution.total, 0);
      expect(distribution.bands(), isEmpty);
      expect(distribution.shareLabel(0), '0%');
    },
  );
  test(
    'Wide negative and positive scores form bounded contiguous truthful ranges',
    () {
      final distribution = ScoreDistribution.fromTracks(
        [a, b, c],
        {
          'a': const Rating(-100000, 0),
          'b': const Rating(0, 0),
          'c': const Rating(1000000, 0),
        },
      );
      final bands = distribution.bands();
      expect(bands.length, lessThanOrEqualTo(20));
      expect(bands.first.low, -100000);
      expect(bands.last.high, 1000000);
      expect(bands.fold(0, (n, b) => n + b.count), 3);
      for (var i = 1; i < bands.length; i++) {
        expect(bands[i].low, bands[i - 1].high + 1);
      }
      for (final score in distribution.counts.keys) {
        expect(bands.where((b) => b.contains(score)), hasLength(1));
      }
      expect(bands.any((b) => b.label.contains('–')), true);
      expect(() => distribution.bands(maxBands: 1), throwsArgumentError);
    },
  );
  test(
    'Single score and Russian labels preserve exact counts and percentages',
    () {
      final distribution = ScoreDistribution.fromTracks(
        [a, b],
        {'a': const Rating(21, 0), 'b': const Rating(21, 0)},
      );
      expect(distribution.bands().single.label, '21 балл');
      expect(distribution.bands().single.count, 2);
      expect(distribution.shareLabel(2), '100%');
      expect(songCountLabel(1), '1 песня');
      expect(songCountLabel(22), '22 песни');
      expect(songCountLabel(111), '111 песен');
      expect(const ScoreBand(2, 2, 1).label, '2 балла');
      expect(const ScoreBand(11, 11, 1).label, '11 баллов');
    },
  );
}
