import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zvuk_personal/data/discovery_store.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  sqfliteFfiInit();
  late LibraryStore library;
  late DiscoveryStore store;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('discovery-test');
    library = await LibraryStore.open(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
    store = DiscoveryStore(library);
  });
  tearDown(() async {
    await library.close();
    await directory.delete(recursive: true);
  });
  test('Offers survive reopening, expire, isolate accounts and reset independently of blocks', () async {
    final now = DateTime.utc(2026, 11, 6);
    const hidden = Track(
      id: 'blocked',
      title: 'Blocked',
      canonicalTrackId: 'master',
    );
    await store.hide('a', hidden);
    await store.offered(
      'a',
      [const Track(id: 'fresh', title: 'Fresh')],
      now,
      cursors: {'seed': 50},
    );
    final reopened = DiscoveryStore(library);
    var m = await reopened.load('a');
    expect(m.excluded(now), containsAll(['fresh', 'blocked', 'master']));
    expect(m.cursors, {'seed': 50});
    expect((await store.load('b')).excluded(now), isEmpty);
    expect(m.excluded(now.add(const Duration(days: 8))), {'blocked', 'master'});
    await store.resetRecent('a');
    m = await store.load('a');
    expect(m.excluded(now), {'blocked', 'master'});
    expect(m.cursors, isEmpty);
    await store.restore('a', hidden);
    expect((await store.load('a')).hidden, isEmpty);
  });
  test('Concurrent updates preserve hidden tracks and offers; memory remains bounded', () async {
    final now = DateTime.utc(2026);
    await Future.wait([
      store.hide('a', const Track(id: 'hidden', title: 'Hidden')),
      store.offered(
        'a',
        List.generate(2100, (i) => Track(id: '$i', title: '$i')),
        now,
      ),
    ]);
    final memory = await store.load('a');
    expect(memory.hidden.single.id, 'hidden');
    expect(memory.offered.length, 2000);
    expect(await library.loadTracks('a', 'favorites'), isEmpty);
    expect(await library.ratings('a'), isEmpty);
  });
}
