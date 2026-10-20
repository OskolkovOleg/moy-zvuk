import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  sqfliteFfiInit();
  final factory = Platform.isAndroid
      ? native.databaseFactory
      : databaseFactoryFfi;
  late Directory dir;
  late LibraryStore store;
  const fresh = Track(id: 'new', title: 'Новая');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('score-policy');
    store = await LibraryStore.open(
      factory: factory,
      databasePath: '${dir.path}/library.db',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'New song starts at nine; plus collects once, minus never removes',
    () async {
      expect(trackScore(fresh.id, await store.ratings('a')), 9);
      await store.vote('a', fresh, 1, addToLibrary: true);
      expect(trackScore(fresh.id, await store.ratings('a')), 10);
      expect((await store.loadTracks('a', 'favorites')).single.id, fresh.id);
      expect((await store.pendingFavoriteAdds('a')).single.id, fresh.id);
      await store.vote('a', fresh, 1, addToLibrary: true);
      expect(await store.pendingFavoriteAdds('a'), hasLength(1));
      for (var i = 0; i < 15; i++) {
        await store.vote('a', fresh, -1);
      }
      expect(trackScore(fresh.id, await store.ratings('a')), -4);
      expect(await store.loadTracks('a', 'favorites'), hasLength(1));
      expect(await store.loadTracks('b', 'favorites'), isEmpty);
    },
  );

  test(
    'Local addition survives restart and remote read without the song',
    () async {
      await store.vote('a', fresh, 1, addToLibrary: true);
      await store.close();
      store = await LibraryStore.open(
        factory: factory,
        databasePath: '${dir.path}/library.db',
      );
      expect((await store.mergeFavorites('a', [])).single.id, fresh.id);
      expect(trackScore(fresh.id, await store.ratings('a')), 10);
      await store.completeFavoriteAdd('a', fresh.id);
      expect(await store.pendingFavoriteAdds('a'), isEmpty);
      expect(await store.loadTracks('a', 'favorites'), hasLength(1));
    },
  );

  test(
    'Undo and v2 backups preserve nine baseline without collecting twice',
    () async {
      final event = await store.vote('a', fresh, 1, addToLibrary: true);
      final backup = await store.exportRatings('a');
      expect(jsonDecode(backup)['version'], 2);
      await store.undo('a', event);
      expect(await store.importRatings('a', backup), 0);
      expect(trackScore(fresh.id, await store.ratings('a')), 9);
      expect(await store.loadTracks('a', 'favorites'), hasLength(1));
      expect(await store.pendingFavoriteAdds('a'), hasLength(1));
    },
  );

  test(
    'v2 migration preserves old favorite and vote scores, queue and downloads',
    () async {
      final path = '${dir.path}/legacy.db';
      const liked = Track(id: 'liked', title: 'Прежняя любимая');
      final db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE votes (account TEXT, id TEXT, track TEXT, delta INTEGER, created TEXT, undone INTEGER, metadata TEXT, PRIMARY KEY(account,id))',
            );
            await db.execute(
              'CREATE TABLE state (account TEXT, key TEXT, value TEXT, PRIMARY KEY(account,key))',
            );
            await db.execute(
              'CREATE TABLE downloads (account TEXT, track TEXT, metadata TEXT, file TEXT, state TEXT, bytes INTEGER, created TEXT, error TEXT, PRIMARY KEY(account,track))',
            );
          },
        ),
      );
      await db.insert('votes', {
        'account': 'a',
        'id': 'old-vote',
        'track': fresh.id,
        'delta': -1,
        'created': '2026-10-01',
        'undone': 0,
        'metadata': jsonEncode(fresh.toJson()),
      });
      await db.insert('state', {
        'account': 'a',
        'key': 'list:favorites',
        'value': jsonEncode([liked.toJson()]),
      });
      await db.insert('state', {
        'account': 'a',
        'key': 'queue',
        'value': '{"index":2,"position":42000}',
      });
      await db.insert('downloads', {
        'account': 'a',
        'track': liked.id,
        'metadata': jsonEncode(liked.toJson()),
        'file': 'kept.audio',
        'state': 'ready',
        'bytes': 123,
        'created': '2026-10-01',
      });
      final originalVotes = await db.query('votes');
      final originalDownloads = await db.query('downloads');
      await db.close();
      final upgraded = await LibraryStore.open(
        factory: factory,
        databasePath: path,
      );
      try {
        final ratings = await upgraded.ratings('a');
        expect(trackScore(liked.id, ratings), 10);
        expect(trackScore(fresh.id, ratings), 9);
        expect(trackScore('unseen', ratings), 9);
        expect(await upgraded.get('a', 'queue'), {
          'index': 2,
          'position': 42000,
        });
        expect(await upgraded.db.query('votes'), originalVotes);
        expect(await upgraded.db.query('downloads'), originalDownloads);
        await upgraded.vote('a', fresh, 1);
        expect(trackScore(fresh.id, await upgraded.ratings('a')), 10);
      } finally {
        await upgraded.close();
      }
    },
  );
}
