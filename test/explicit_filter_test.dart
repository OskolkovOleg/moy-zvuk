import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/data/genre_filter.dart';
import 'package:zvuk_personal/data/library_display_order.dart';
import 'package:zvuk_personal/data/library_filter.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  test('Only boolean explicit metadata is trusted; old and malformed data stays unknown', () {
    for (final value in [true, false, null, 'false', 0, <String, dynamic>{}]) {
      final raw = {'id': 'song', 'title': 'Song', 'explicit': value};
      final expected = value is bool ? value : null;
      for (final track in [Track.fromApi(raw), Track.fromJson(raw)]) {
        expect(track.explicit, expected);
        final restored = Track.fromJson(jsonDecode(jsonEncode(track.toJson())));
        expect(restored.explicit, expected);
      }
    }
    expect(Track.fromJson({'id': 'old', 'title': 'Old'}).explicit, isNull);
  });

  test('Track hydration requests explicit and retains false, true and unknown in source order', () async {
    final api = ZvukApi(
      'fixture',
      client: MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['operationName'], 'getTracks');
        expect(body['query'], contains('duration explicit genres'));
        return http.Response(
          jsonEncode({
            'data': {
              'getTracks': [
                {'id': 'dirty', 'title': 'Same title', 'explicit': true},
                {'id': 'clean', 'title': 'Same title', 'explicit': false},
                {'id': 'old', 'title': 'Unknown'},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final tracks = await api.tracks([
      'clean',
      'dirty',
      'old',
      'missing',
      'clean',
    ]);
    expect(tracks.map((t) => t.explicit), [false, true, null, null, false]);
    expect(tracks.map((t) => t.id), [
      'clean',
      'dirty',
      'old',
      'missing',
      'clean',
    ]);
  });

  const rock = [TrackGenre(id: 'r', name: 'Rock')];
  const clean = Track(
    id: 'clean',
    title: 'Clean',
    genres: rock,
    explicit: false,
  );
  const dirty = Track(
    id: 'dirty',
    title: 'Clean',
    genres: rock,
    explicit: true,
  );
  const unknown = Track(id: 'unknown', title: 'Clean', genres: rock);
  const pop = Track(id: 'pop', title: 'Pop', explicit: false);
  const source = [pop, clean, dirty, unknown, clean];
  const ratings = {
    'clean': Rating(10, 1),
    'dirty': Rating(13, 4),
    'unknown': Rating(12, 3),
  };

  test('Censored selection intersects genres and inclusive scores, preserving occurrences', () {
    final filter = LibraryFilter(
      minScore: 10,
      maxScore: 13,
      genres: {GenreGroup.rock},
      censoredOnly: true,
    );
    expect(source.where((t) => filter.matches(t, ratings)), [clean, clean]);
    expect(
      filterTracksByGenreAndScore(
        source,
        ratings,
        groups: {GenreGroup.rock},
        minScore: 10,
        maxScore: 13,
        censoredOnly: true,
      ),
      [clean, clean],
    );
    expect(source.where((t) => LibraryFilter.all.matches(t, ratings)), source);
    expect(LibraryFilter(censoredOnly: true).label, 'Цензурные');
    expect(LibraryFilter(censoredOnly: true).isActive, true);
    expect(LibraryFilter(censoredOnly: true), isNot(LibraryFilter.all));
    expect(
      LibraryFilter(censoredOnly: true),
      LibraryFilter(censoredOnly: true),
    );
  });

  test('Changing the censored filter re-evaluates eligibility; unknown metadata is never assumed clean', () {
    final order = LibraryDisplayOrder();
    final filter = LibraryFilter(censoredOnly: true);
    expect(
      order
          .arrange('owner', 'favorites', source, ratings, filter: filter)
          .map((t) => t.id),
      ['clean', 'clean', 'pop'],
    );
    expect(
      order.arrange('owner', 'favorites', source, ratings).map((t) => t.id),
      ['dirty', 'unknown', 'clean', 'clean', 'pop'],
    );
    expect(
      order
          .arrange('owner', 'favorites', source, ratings, filter: filter)
          .map((t) => t.id),
      ['clean', 'clean', 'pop'],
    );
  });
}
