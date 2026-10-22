import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  const a = Track(id: 'a', title: 'A');
  const b = Track(id: 'b', title: 'B');
  const c = Track(id: 'c', title: 'C');

  test(
    'Every new unvoted song starts at nine, including uncached/new tracks',
    () {
      expect(trackScore('new-song', {}), 9);
      expect(trackScore('a', {'a': const Rating(9, 1)}), 9);
    },
  );

  test('Equal scores share a rank range that updates with votes', () {
    final scores = {'a': const Rating(12, 2), 'c': const Rating(11, 1)};
    final source = [c, a, b];
    expect(ratingPosition(source, scores, 'b')!.label, '3');
    expect(ratingPosition(source, scores, 'b')!.total, 3);
    scores['b'] = const Rating(12, 2);
    for (final id in ['a', 'b']) {
      final rank = ratingPosition(source, scores, id)!;
      expect((rank.start, rank.end), (1, 2));
      expect(rank.label, '1–2');
    }
    scores['b'] = const Rating(13, 3);
    expect(ratingPosition(source, scores, 'b')!.label, '1');
    scores['b'] = const Rating(-1, 11);
    expect(ratingPosition(source, scores, 'b')!.label, '3');
    expect(rankedTracks(source, scores), hasLength(3));
    expect(source, [c, a, b]);
  });

  test('Seven equal leaders share places one through seven in any order', () {
    final leaders = List.generate(7, (i) => Track(id: '$i', title: '$i'));
    for (final source in [leaders, leaders.reversed.toList()]) {
      for (final track in source) {
        final rank = ratingPosition(source, {}, track.id)!;
        expect((rank.start, rank.end, rank.total), (1, 7, 7));
        expect(rank.label, '1–7');
      }
    }
  });

  test(
    'A middle group shares places 78 through 90, including negative scores',
    () {
      final tracks = List.generate(100, (i) => Track(id: '$i', title: '$i'));
      final scores = {
        for (var i = 0; i < 100; i++)
          '$i': Rating(i < 77 ? 10 : (i < 90 ? -2 : -3), 0),
      };
      for (final source in [tracks, tracks.reversed.toList()]) {
        for (var i = 77; i < 90; i++) {
          final rank = ratingPosition(source, scores, '$i')!;
          expect((rank.start, rank.end, rank.total), (78, 90, 100));
          expect(rank.label, '78–90');
        }
      }
    },
  );

  test(
    'Outside tracks have no invented rank; duplicate entries share the range',
    () {
      expect(ratingPosition([], {}, 'a'), isNull);
      expect(ratingPosition([a], {}, 'missing'), isNull);
      final position = ratingPosition([b, a, b], {}, 'b')!;
      expect(position.label, '1–3');
      expect(position.total, 3);
    },
  );
}
