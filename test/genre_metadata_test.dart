import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  test('Legacy track JSON has no invented genre or source', () {
    final track = Track.fromJson({'id': 'old', 'title': 'Old track'});
    expect(track.genres, isEmpty);
    expect(track.genreSource, isNull);
    expect(Track.fromJson(track.toJson()).genres, isEmpty);
  });

  test('Track genres take precedence over conflicting release genres', () {
    final track = Track.fromApi({
      'id': 'lipstick',
      'title': 'LIPSTICK',
      'genres': [
        {'id': 39, 'name': 'Hip-Hop', 'shortName': ''},
        {'id': '149', 'name': 'Trap', 'shortName': null},
      ],
      'release': {
        'id': 'heavy-metal',
        'genres': [
          {'id': '24', 'name': 'Alternative Rock'},
        ],
      },
    });
    expect(track.genreSource, GenreSource.track);
    expect(track.genres.map((g) => g.id), ['39', '149']);
    expect(track.genres.map((g) => g.name), ['Hip-Hop', 'Trap']);
    expect(track.genres.first.shortName, '');
    expect(track.releaseId, 'heavy-metal');

    final restored = Track.fromJson(jsonDecode(jsonEncode(track.toJson())));
    expect(restored.toJson(), track.toJson());
    expect(restored.genreSource, GenreSource.track);
  });

  test('Missing or empty track genres fall back to the release', () {
    for (final ownGenres in [null, <dynamic>[]]) {
      final track = Track.fromApi({
        'id': 'song',
        'genres': ownGenres,
        'release': {
          'genres': [
            {'id': '57', 'name': 'Russian Rock', 'shortName': 'Rock'},
          ],
        },
      });
      expect(track.genreSource, GenreSource.release);
      expect(track.genres.single.name, 'Russian Rock');
      expect(track.genres.single.shortName, 'Rock');
      expect(Track.fromJson(track.toJson()).genreSource, GenreSource.release);
    }
  });

  test('Unknown genre names remain original track metadata', () {
    final track = Track.fromApi({
      'id': 'unknown',
      'genres': [
        {'id': 'future', 'name': 'An Unmapped Future Style'},
      ],
      'release': {
        'genres': [
          {'id': '23', 'name': 'Rock'},
        ],
      },
    });
    expect(track.genreSource, GenreSource.track);
    expect(track.genres.single.name, 'An Unmapped Future Style');
    expect(Track.fromJson(track.toJson()).genres.single.id, 'future');
  });

  test('Malformed optional genres cannot break a track or hide a fallback', () {
    final track = Track.fromApi({
      'id': 'song',
      'genres': [
        null,
        42,
        {},
        {'name': '  '},
        {'name': 1},
      ],
      'release': {
        'genres': [
          {'id': '52', 'name': 'Classical'},
        ],
      },
    });
    expect(track.genreSource, GenreSource.release);
    expect(track.genres.single.name, 'Classical');
    final empty = Track.fromApi({'id': 'empty', 'genres': 'not a list'});
    expect(empty.genres, isEmpty);
    expect(empty.genreSource, isNull);
  });

  test('An unknown cached source is not relabeled as track metadata', () {
    final track = Track.fromJson({
      'id': 'future',
      'title': 'Future cache',
      'genres': [
        {'id': '23', 'name': 'Rock'},
      ],
      'genreSource': 'external',
    });
    expect(track.genres.single.name, 'Rock');
    expect(track.genreSource, isNull);
  });
}
