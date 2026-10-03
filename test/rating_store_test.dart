import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  const a = Track(id: '1', title: 'Первый');
  const b = Track(id: '2', title: 'Второй');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-test');
    store = await LibraryStore.open(
      factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test('Cumulative votes, undo, account isolation and persistence', () async {
    await store.vote('a', a, 1);
    await store.vote('a', a, 1);
    final minus = await store.vote('a', a, -1);
    expect((await store.ratings('a'))['1']!.score, 11);
    await store.undo('other', minus);
    expect((await store.ratings('a'))['1']!.score, 11);
    await store.undo('a', minus);
    expect((await store.ratings('a'))['1']!.score, 12);
    await store.saveTracks('a', 'favorites', [b, a]);
    await store.close();
    store = await LibraryStore.open(
      factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
    expect((await store.ratings('a'))['1']!.score, 12);
    expect(await store.ratings('other'), isEmpty);
    expect((await store.loadTracks('a', 'favorites')).map((t) => t.id), [
      '2',
      '1',
    ]);
  });
  test(
    'Legacy backups keep vote history and apply the baseline only once',
    () async {
      final legacy = jsonEncode({
        'version': 1,
        'account': 'a',
        'events': [
          {
            'id': 'legacy-minus',
            'track': a.id,
            'delta': -1,
            'created': '2026-10-02T10:00:00Z',
            'undone': false,
            'metadata': a.toJson(),
          },
        ],
      });
      expect(await store.importRatings('a', legacy), 1);
      expect(trackScore(a.id, await store.ratings('a')), 9);
      expect(await store.importRatings('a', legacy), 0);
      final exported = jsonDecode(await store.exportRatings('a'));
      expect(exported['events'], hasLength(1));
      expect(exported['events'][0]['delta'], -1);
      expect(trackScore(a.id, await store.ratings('a')), 9);
      await store.undo('a', 'legacy-minus');
      expect(trackScore(a.id, await store.ratings('a')), 10);
      await store.importRatings('a', legacy);
      expect(trackScore(a.id, await store.ratings('a')), 10);
      expect(trackScore('new-song', await store.ratings('a')), 10);
    },
  );
  test(
    'Repeated import does not duplicate, undo survives old backup',
    () async {
      final id = await store.vote('a', a, 1);
      final backup = await store.exportRatings('a');
      await store.undo('a', id);
      expect(await store.importRatings('a', backup), 0);
      expect(await store.importRatings('a', backup), 0);
      expect(await store.ratings('a'), isEmpty);
      expect(trackScore(a.id, await store.ratings('a')), 10);
      await expectLater(
        store.importRatings('b', backup),
        throwsFormatException,
      );
    },
  );
  test(
    'Import validates atomically, conflicts roll back earlier inserts',
    () async {
      await store.vote('a', a, 1);
      final data = jsonDecode(await store.exportRatings('a'));
      final old = Map<String, dynamic>.from(data['events'][0]);
      data['events'] = [
        {...old, 'id': 'new'},
        {...old, 'delta': -1},
      ];
      await expectLater(
        store.importRatings('a', jsonEncode(data)),
        throwsFormatException,
      );
      expect((await store.ratings('a'))['1']!.score, 11);
      data['events'] = [
        {...old, 'delta': 100},
      ];
      await expectLater(
        store.importRatings('a', jsonEncode(data)),
        throwsFormatException,
      );
    },
  );
  test('Baseline after balanced votes differs from unrated and ties preserve order', () async {
    await store.vote('a', a, 1);
    await store.vote('a', a, -1);
    final ratings = await store.ratings('a');
    expect(rankedTracks([b, a], ratings).map((t) => t.id), ['2', '1']);
    expect(rankedTracks([b, a], ratings, unrated: true).map((t) => t.id), [
      '2',
    ]);
    await store.vote('a', a, 1);
    expect(rankedTracks([b, a], await store.ratings('a')).first.id, '1');
  });
  test('Scores can go below zero; undo is idempotent', () async {
    for (var i = 0; i < 11; i++) {
      await store.vote('a', a, -1);
    }
    await store.saveTracks('a', 'favorites', [a, b]);
    final last = await store.vote('a', a, -1);
    expect((await store.ratings('a'))['1']!.score, -2);
    expect(
      rankedTracks(
        await store.loadTracks('a', 'favorites'),
        await store.ratings('a'),
      ).map((t) => t.id),
      ['2', '1'],
    );
    await store.undo('a', last);
    await store.undo('a', last);
    expect((await store.ratings('a'))['1']!.score, -1);
  });

  test(
    'Manual order reconciles new and missing songs without losing duplicates',
    () {
      const c = Track(id: '3', title: 'Новый');
      expect(
        manuallyOrderedTracks(
          [a, b, a, c],
          ['2', 'missing', '1', '1', '1'],
        ).map((t) => t.id),
        ['2', '1', '1', '3'],
      );
      expect(manuallyOrderedTracks([a, c], ['2', '1']).map((t) => t.id), [
        '1',
        '3',
      ]);
      expect(manuallyOrderedTracks([b, a], []).map((t) => t.id), ['2', '1']);
    },
  );

  test(
    'Arrangements survive reopening and are scoped to account and list',
    () async {
      await store.saveOrder('a', 'favorites', ['2', '1']);
      await store.saveOrder('a', 'playlist', ['1', '2']);
      await store.vote('a', a, 1);
      await store.close();
      store = await LibraryStore.open(
        factory: Platform.isAndroid
            ? native.databaseFactory
            : databaseFactoryFfi,
        databasePath: '${directory.path}/test.db',
      );
      expect(await store.loadOrder('a', 'favorites'), ['2', '1']);
      expect(await store.loadOrder('a', 'playlist'), ['1', '2']);
      expect(await store.loadOrder('other', 'favorites'), isEmpty);
      expect((await store.ratings('a'))['1']!.score, 11);
    },
  );

  test(
    'Backup restores missing arrangements and preserves local changes',
    () async {
      await store.saveOrder('a', 'favorites', ['2', '1', '2']);
      await store.saveOrder('a', 'playlist', ['1', '2']);
      final backup = await store.exportRatings('a');
      await store.db.delete('state');
      expect(await store.importRatings('a', backup), 0);
      expect(await store.loadOrder('a', 'favorites'), ['2', '1', '2']);
      await store.saveOrder('a', 'favorites', ['1', '2', '2']);
      await store.importRatings('a', backup);
      expect(await store.loadOrder('a', 'favorites'), ['1', '2', '2']);
      final legacy = jsonDecode(backup) as Map<String, dynamic>;
      legacy.remove('orders');
      await store.importRatings('a', jsonEncode(legacy));
      expect(await store.loadOrder('a', 'playlist'), ['1', '2']);
    },
  );

  test('Malformed order rejects entire backup before changing votes', () async {
    await store.vote('a', a, 1);
    final backup = jsonDecode(await store.exportRatings('a'));
    backup['events'][0]['id'] = 'new-event';
    backup['orders'] = {
      'favorites': ['1', 23],
    };
    await expectLater(
      store.importRatings('a', jsonEncode(backup)),
      throwsFormatException,
    );
    expect((await store.ratings('a'))['1']!.score, 11);
    expect(await store.loadOrder('a', 'favorites'), isEmpty);
  });
}
