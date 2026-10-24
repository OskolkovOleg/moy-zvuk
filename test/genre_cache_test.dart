import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:zvuk_personal/data/genre_filter.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  Future<LibraryStore> openStore() => LibraryStore.open(
    factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
    databasePath: '${directory.path}/test.db',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-genre-test');
    store = await openStore();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'Legacy list cache reads alongside new metadata without a migration',
    () async {
      await store.put('owner', 'list:old', [
        {'id': 'old', 'title': 'Before genres'},
      ]);
      final old = (await store.loadTracks('owner', 'old')).single;
      expect(old.genres, isEmpty);
      expect(old.genreSource, isNull);
      expect(trackScore(old.id, await store.ratings('owner')), 9);
    },
  );

  test('List and pending favorite caches retain genres, provenance and scores after reopen', () async {
    final fromTrack = Track.fromApi({
      'id': 'track',
      'title': 'Crossover',
      'genres': [
        {'id': '43', 'name': 'Pop'},
        {'id': '39', 'name': 'Hip-Hop'},
      ],
    });
    final fromRelease = Track.fromApi({
      'id': 'release',
      'title': 'Release fallback',
      'release': {
        'genres': [
          {'id': '23', 'name': 'Rock'},
        ],
      },
    });
    await store.saveTracks('owner', 'playlist', [fromRelease, fromTrack]);
    await store.vote('owner', fromTrack, 1, addToLibrary: true);
    await store.close();
    store = await openStore();

    final cached = await store.loadTracks('owner', 'playlist');
    expect(cached.map((t) => t.toJson()), [
      fromRelease.toJson(),
      fromTrack.toJson(),
    ]);
    expect(cached.first.genreSource, GenreSource.release);
    final favorites = await store.loadTracks('owner', 'favorites');
    expect(favorites.single.toJson(), fromTrack.toJson());
    final pending = await store.pendingFavoriteAdds('owner');
    expect(pending.single.genreSource, GenreSource.track);
    expect(genreGroupsFor(pending.single), {GenreGroup.pop, GenreGroup.hipHop});
    final ratings = await store.ratings('owner');
    expect(trackScore(fromTrack.id, ratings), 10);
    expect(trackScore(fromRelease.id, ratings), 9);
    expect(
      filterTracksByGenreAndScore(
        cached,
        ratings,
        groups: {GenreGroup.hipHop},
        minScore: 10,
      ).map((t) => t.id),
      ['track'],
    );
    expect(await store.loadTracks('other', 'playlist'), isEmpty);
  });

  test(
    'Normal library refresh hydrates genres into an older cached track',
    () async {
      await store.put('owner', 'list:favorites', [
        {'id': 'track', 'title': 'Cached before genres'},
      ]);
      final fresh = Track.fromApi({
        'id': 'track',
        'title': 'Fresh metadata',
        'genres': [
          {'id': 'future', 'name': 'Future Unmapped Genre'},
        ],
      });
      await store.mergeFavorites('owner', [fresh]);
      final cached = (await store.loadTracks('owner', 'favorites')).single;
      expect(cached.genres.single.name, 'Future Unmapped Genre');
      expect(cached.genreSource, GenreSource.track);
      expect(genreGroupsFor(cached), isEmpty);
      expect(trackScore(cached.id, await store.ratings('owner')), 9);
    },
  );
}
