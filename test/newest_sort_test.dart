import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/listening_stats.dart';
import 'package:zvuk_personal/data/models.dart';

import 'collection_controller_test.dart' show UnusedMusic;

class _DelayedOrderStore implements LibraryStore {
  final order = Completer<bool>();
  @override
  Future<dynamic> get(String account, String key) => order.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const a = Track(id: 'a', title: 'A'),
      b = Track(id: 'b', title: 'B'),
      c = Track(id: 'c', title: 'C');
  test(
    'Newest preserves addition order regardless of scores or listening dates',
    () {
      final stats = ListeningStats(
        DateTime.now(),
        last: {'c': DateTime.utc(2020)},
      );
      final source = [a, b, c];
      final result = sortedLibraryTracks(
        source,
        {'a': const Rating(9, 0), 'c': const Rating(100, 91)},
        sort: LibrarySort.newest,
        stats: stats,
      );
      expect(result.map((t) => t.id), ['a', 'b', 'c']);
      result.clear();
      expect(source, hasLength(3));
    },
  );

  test(
    'A delayed newest selection cannot override a later sort or list',
    () async {
      final store = _DelayedOrderStore();
      final app = AppController(store, UnusedMusic())
        ..account = const Account('owner', 'Fixture')
        ..tracks = [a, b];
      final pending = app.setLibrarySort(LibrarySort.newest);
      await app.setLibrarySort(LibrarySort.scores);
      store.order.complete(true);
      await pending;
      expect(app.librarySort, LibrarySort.scores);
      app.listId = 'playlist';
      await app.setLibrarySort(LibrarySort.newest);
      expect(app.librarySort, LibrarySort.scores);
      app.dispose();
    },
  );

  group('Addition order cache', () {
    late LibraryStore store;
    late Directory directory;
    setUp(() async {
      sqfliteFfiInit();
      directory = await Directory.systemTemp.createTemp('newest-sort');
      store = await LibraryStore.open(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/test.db',
      );
    });
    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    test(
      'Local additions merge newest first and stay put after repeated votes',
      () async {
        await store.mergeFavorites('owner', [c]);
        await store.vote('owner', a, 1, addToLibrary: true);
        await store.vote('owner', b, 1, addToLibrary: true);
        await store.vote('owner', a, 1, addToLibrary: true);
        expect(
          (await store.loadTracks('owner', 'favorites')).map((t) => t.id),
          ['b', 'a', 'c'],
        );
        expect((await store.mergeFavorites('owner', [c])).map((t) => t.id), [
          'b',
          'a',
          'c',
        ]);
        // Sync retains chronological order so the server records B after A.
        expect((await store.pendingFavoriteAdds('owner')).map((t) => t.id), [
          'a',
          'b',
        ]);
        await store.completeFavoriteAdd('owner', 'a');
        await store.completeFavoriteAdd('owner', 'b');
        expect(
          (await store.mergeFavorites('owner', [b, a, c])).map((t) => t.id),
          ['b', 'a', 'c'],
        );
        await store.close();
        store = await LibraryStore.open(
          factory: databaseFactoryFfi,
          databasePath: '${directory.path}/test.db',
        );
        expect(await store.hasFavoriteAdditionOrder('owner'), true);
        expect(await store.hasFavoriteAdditionOrder('other'), false);
        expect(
          (await store.loadTracks('owner', 'favorites')).map((t) => t.id),
          ['b', 'a', 'c'],
        );
      },
    );
    test(
      'Unknown offline legacy order keeps the current sort with an explanation',
      () async {
        await store.saveTracks('owner', 'favorites', [a, b]);
        final app = AppController(store, UnusedMusic())
          ..account = const Account('owner', 'Fixture')
          ..tracks = [a, b];
        await app.setLibrarySort(LibrarySort.newest);
        expect(app.librarySort, LibrarySort.scores);
        expect(app.message, contains('при подключении к интернету'));
        expect(await store.hasFavoriteAdditionOrder('owner'), false);
        app.dispose();
      },
    );
    test('Confirmed cached order works offline, without history reads or changing playback', () async {
      final ordered = await store.mergeFavorites('owner', [b, c, a]);
      final music = UnusedMusic();
      final app = AppController(store, music)
        ..account = const Account('owner', 'Fixture')
        ..tracks = ordered
        ..favoriteTracks = ordered
        ..ratings = {'a': const Rating(20, 11)};
      await app.setLibrarySort(LibrarySort.newest);
      expect(app.librarySort, LibrarySort.newest);
      expect(app.visibleTracks.map((t) => t.id), ['b', 'c', 'a']);
      expect(app.listeningStats, null);
      expect(app.libraryHistoryLoading, false);
      expect(music.played, isEmpty);
      await app.playVisible();
      expect(music.played.map((t) => t.id), ['b', 'c', 'a']);
      app.account = const Account('other', 'Other');
      expect(app.librarySort, LibrarySort.scores);
      await app.setLibrarySort(LibrarySort.newest);
      expect(app.librarySort, LibrarySort.scores);
      app.dispose();
    });
  });
}
