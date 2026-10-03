import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  const a = Track(id: 'a', title: 'A');
  const b = Track(id: 'b', title: 'B');
  const c = Track(id: 'c', title: 'C');

  test('Every unvoted song starts at ten, including uncached/new tracks', () {
    expect(trackScore('new-song', {}), 10);
    expect(trackScore('a', {'a': const Rating(9, 1)}), 9);
  });

  test(
    'Rating position uses the full list, keeps ties and updates with votes',
    () {
      final scores = {'a': const Rating(12, 2), 'c': const Rating(11, 1)};
      final source = [c, a, b];
      expect(ratingPosition(source, scores, 'b')!.position, 3);
      expect(ratingPosition(source, scores, 'b')!.total, 3);
      scores['b'] = const Rating(12, 2);
      expect(ratingPosition(source, scores, 'a')!.position, 1);
      expect(ratingPosition(source, scores, 'b')!.position, 2);
      scores['b'] = const Rating(13, 3);
      expect(ratingPosition(source, scores, 'b')!.position, 1);
      scores['b'] = const Rating(-1, 11);
      expect(ratingPosition(source, scores, 'b')!.position, 3);
      expect(rankedTracks(source, scores), hasLength(3));
      expect(source, [c, a, b]);
    },
  );

  test('Outside tracks have no invented rank; duplicate ranks use first occurrence', () {
    expect(ratingPosition([], {}, 'a'), isNull);
    expect(ratingPosition([a], {}, 'missing'), isNull);
    final position = ratingPosition([b, a, b], {}, 'b')!;
    expect(position.position, 1);
    expect(position.total, 3);
  });
}
