import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/library_display_order.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/genre_filter.dart';
import 'package:zvuk_personal/data/library_filter.dart';

void main() {
  const a = Track(id: 'a', title: 'A');
  const b = Track(id: 'b', title: 'B');
  const c = Track(id: 'c', title: 'C');

  test(
    'Repeated score changes keep rows in place until explicitly resorted',
    () {
      final order = LibraryDisplayOrder();
      final scores = {'a': const Rating(12, 3), 'c': const Rating(10, 1)};
      List<String> ids() => order
          .arrange('owner', 'favorites', [c, b, a], scores)
          .map((t) => t.id)
          .toList();
      expect(ids(), ['a', 'c', 'b']);
      for (var score = 10; score < 30; score++) {
        scores['b'] = Rating(score, score - 9);
        expect(ids(), ['a', 'c', 'b']);
      }
      order.reset();
      expect(ids(), ['b', 'a', 'c']);
      scores['b'] = const Rating(-5, 99);
      expect(ids(), ['b', 'a', 'c']);
      order.reset();
      expect(ids(), ['a', 'c', 'b']);
    },
  );

  test('A new list or account starts in current score order', () {
    final order = LibraryDisplayOrder();
    final scores = <String, Rating>{};
    order.arrange('owner', 'favorites', [a, b], scores);
    scores['b'] = const Rating(20, 11);
    expect(order.arrange('owner', 'favorites', [a, b], scores).first.id, 'a');
    expect(order.arrange('owner', 'playlist', [a, b], scores).first.id, 'b');
    scores['a'] = const Rating(30, 21);
    expect(order.arrange('other', 'playlist', [a, b], scores).first.id, 'a');
  });

  test('Membership and metadata update without moving existing rows', () {
    final order = LibraryDisplayOrder();
    order.arrange('owner', 'p', [a, b, a], {});
    const renamed = Track(id: 'a', title: 'Fresh title');
    final source = [c, renamed, b, renamed];
    final visible = order.arrange('owner', 'p', source, {
      'c': const Rating(50, 41),
    });
    expect(visible.map((t) => t.id), ['a', 'b', 'a', 'c']);
    expect(visible.first.title, 'Fresh title');
    expect(source.map((t) => t.id), ['c', 'a', 'b', 'a']);
    expect(order.arrange('owner', 'p', [c, b, renamed], {}).map((t) => t.id), [
      'a',
      'b',
      'c',
    ]);
    expect(order.arrange('owner', 'p', [], {}), isEmpty);
    expect(order.arrange('owner', 'p', [c, a], {}).map((t) => t.id), [
      'c',
      'a',
    ]);
  });

  test('Filtered membership stays fixed during votes, resets on refresh and respects new tracks', () {
    const rockA = Track(
      id: 'a',
      title: 'A',
      genres: [TrackGenre(id: 'r', name: 'Rock')],
    );
    const rockB = Track(
      id: 'b',
      title: 'B',
      genres: [TrackGenre(id: 'r', name: 'Rock')],
    );
    const rockC = Track(
      id: 'c',
      title: 'C',
      genres: [TrackGenre(id: 'r', name: 'Rock')],
    );
    const pop = Track(
      id: 'p',
      title: 'Pop',
      genres: [TrackGenre(id: 'p', name: 'Pop')],
    );
    final scores = {
      'a': const Rating(10, 1),
      'b': const Rating(9, 0),
      'c': const Rating(12, 3),
      'p': const Rating(13, 4),
    };
    final filter = LibraryFilter(
      minScore: 10,
      maxScore: 13,
      genres: {GenreGroup.rock},
    );
    final order = LibraryDisplayOrder();
    List<String> visible(List<Track> source) => order
        .arrange('owner', 'favorites', source, scores, filter: filter)
        .map((t) => t.id)
        .toList();
    expect(visible([rockA, rockB, pop]), ['a']);
    scores['a'] = const Rating(8, 3);
    scores['b'] = const Rating(11, 2);
    expect(visible([rockA, rockB, pop]), ['a']);
    expect(visible([rockA, rockB, rockC, pop]), ['a', 'c']);
    order.reset();
    expect(visible([rockA, rockB, rockC, pop]), ['c', 'b']);
    expect(
      order
          .arrange('owner', 'favorites', [rockA, rockB, rockC, pop], scores)
          .map((t) => t.id),
      ['p', 'c', 'b', 'a'],
    );
  });
}
