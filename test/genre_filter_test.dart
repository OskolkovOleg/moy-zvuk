import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/genre_filter.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/shuffle_tracks.dart';

void main() {
  const rock = Track(
    id: 'rock',
    title: 'Rock song',
    genres: [TrackGenre(id: '23', name: 'Rock')],
    genreSource: GenreSource.track,
  );
  const crossover = Track(
    id: 'crossover',
    title: 'Crossover',
    genres: [
      TrackGenre(id: '43', name: 'Pop'),
      TrackGenre(id: '39', name: 'Hip-Hop'),
    ],
    genreSource: GenreSource.track,
  );
  const untagged = Track(id: 'untagged', title: 'Untagged');
  const unmapped = Track(
    id: 'unmapped',
    title: 'Unknown style',
    genres: [TrackGenre(id: 'future', name: 'Rocking Chair')],
    genreSource: GenreSource.track,
  );

  test('Multiple raw genres and mixed styles produce several broad groups', () {
    expect(genreGroupsFor(crossover), {GenreGroup.pop, GenreGroup.hipHop});
    expect(
      genreGroupsFor(
        const Track(
          id: 'indie',
          title: 'Indie song',
          genres: [TrackGenre(id: '25', name: 'Indie Rock')],
        ),
      ),
      {GenreGroup.rock, GenreGroup.indie},
    );
  });

  test(
    'Known labels normalize case and punctuation without substring guesses',
    () {
      expect(
        genreGroupsFor(
          const Track(
            id: 'rap',
            title: 'Rap song',
            genres: [
              TrackGenre(id: '39', name: ' HIP_HOP '),
              TrackGenre(id: '38', name: 'Rap/R&B'),
            ],
          ),
        ),
        {GenreGroup.hipHop},
      );
      expect(genreGroupsFor(unmapped), isEmpty);
      expect(genreGroupsFor(untagged), isEmpty);
      expect(unmapped.genres.single.name, 'Rocking Chair');
    },
  );

  test('Genre selection is OR, score limits are AND and inclusive', () {
    const ratings = {
      'rock': Rating(12, 3),
      'crossover': Rating(9, 2),
      'unmapped': Rating(20, 11),
    };
    final source = [untagged, rock, crossover, unmapped];
    final selected = filterTracksByGenreAndScore(
      source,
      ratings,
      groups: {GenreGroup.rock, GenreGroup.hipHop},
      minScore: 9,
      maxScore: 12,
    );
    expect(selected, [rock, crossover]);
    expect(
      filterTracksByGenreAndScore(
        source,
        ratings,
        groups: {GenreGroup.pop},
        minScore: 10,
      ),
      isEmpty,
    );
    expect(source, [untagged, rock, crossover, unmapped]);
    expect(trackScore(rock.id, ratings), 12);
    expect(trackScore(untagged.id, ratings), 9);
  });

  test(
    'No selected groups includes unknown and old tracks, preserving order',
    () {
      final source = [unmapped, rock, untagged, rock, crossover];
      final selected = filterTracksByGenreAndScore(
        source,
        const {'rock': Rating(8, 1)},
        minScore: 9,
        maxScore: 9,
      );
      expect(selected, [unmapped, untagged, crossover]);
      expect(filterTracksByGenreAndScore(source, {}), source);
      final rockOnly = filterTracksByGenreAndScore(
        source,
        {},
        groups: {GenreGroup.rock},
      );
      expect(rockOnly, [rock, rock]);
      expect(
        shuffledTracks(rockOnly, {}, random: Random(1)),
        unorderedEquals(rockOnly),
      );
    },
  );

  test(
    'Empty selections and one-sided score ranges work; reversed ranges fail',
    () {
      expect(filterTracksByGenreAndScore([], {}), isEmpty);
      expect(filterTracksByGenreAndScore([rock], {}, maxScore: 8), isEmpty);
      expect(
        () => filterTracksByGenreAndScore([], {}, minScore: 10, maxScore: 9),
        throwsArgumentError,
      );
    },
  );
}
