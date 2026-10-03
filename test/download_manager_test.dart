import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/downloads/download_record.dart';

class DownloadApi extends ZvukApi {
  DownloadApi() : super('test-credential');
  int calls = 0;
  Completer<String>? gate;
  String url = 'https://audio.example/song';
  @override
  Future<String> streamUrl(String id) async {
    calls++;
    return gate == null ? '$url/$id' : await gate!.future;
  }
}

Uint8List audioFixture([int size = 2048]) {
  final bytes = Uint8List(size);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  return bytes;
}

Future<void> waitDownloads(DownloadManager manager) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (manager.pendingCount > 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(manager.pendingCount, 0);
  // Worker cleanup follows its final manifest write.
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  late DownloadManager manager;
  late DownloadApi api;
  final factory = Platform.isAndroid
      ? native.databaseFactory
      : databaseFactoryFfi;
  const a = Track(
    id: 'a',
    title: 'Первый',
    artists: 'Артист',
    artistIds: ['7'],
  );
  const b = Track(id: 'b', title: 'Второй');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-download-test');
    store = await LibraryStore.open(
      factory: factory,
      databasePath: '${directory.path}/test.db',
    );
    api = DownloadApi();
    manager = DownloadManager(
      store,
      clientFactory: () => MockClient((request) async {
        expect(request.headers.containsKey('X-Auth-Token'), false);
        return http.Response.bytes(
          audioFixture(),
          200,
          headers: {'content-type': 'audio/wav'},
        );
      }),
    );
    await manager.configure('one', api);
  });
  tearDown(() async {
    await manager.close();
    api.close();
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'Durable deduplicated downloads retain metadata and isolate accounts',
    () async {
      await store.vote('one', a, -1);
      await store.saveOrder('one', 'favorites', [b.id, a.id]);
      await manager.enqueue([a, a, b]);
      await waitDownloads(manager);
      expect(api.calls, 2);
      expect(manager.tracks.map((t) => t.id), ['a', 'b']);
      expect(manager.storedBytes, 4096);
      final local = await manager.localPath('one', a.id);
      expect(local, isNotNull);
      expect(await File(local!).readAsBytes(), audioFixture());
      await manager.enqueue([a]);
      expect(api.calls, 2);
      await manager.close();
      manager = DownloadManager(store);
      await manager.configure('two', null);
      expect(manager.items, isEmpty);
      expect(await manager.localPath('two', a.id), isNull);
      await manager.configure('one', null);
      expect(manager.tracks.first.artistIds, ['7']);
      expect(await manager.localPath('one', a.id), local);
      await manager.remove(a.id);
      expect(await File(local).exists(), false);
      expect((await store.ratings('one'))[a.id]!.score, 9);
      expect(await store.loadOrder('one', 'favorites'), ['b', 'a']);
      await manager.clear();
      expect(manager.items, isEmpty);
    },
  );

  test(
    'Invalid, partial and oversized streams fail without leaving audio',
    () async {
      await manager.close();
      var call = 0;
      manager = DownloadManager(
        store,
        maxBytes: 4096,
        clientFactory: () => MockClient.streaming((request, body) async {
          final index = call++;
          return switch (index) {
            0 => http.StreamedResponse(
              Stream.value(List.filled(2048, 60)),
              200,
              headers: {'content-type': 'audio/mpeg'},
              contentLength: 2048,
            ),
            1 => http.StreamedResponse(
              Stream.value(audioFixture()),
              200,
              contentLength: 3000,
            ),
            2 => http.StreamedResponse(Stream.value(audioFixture(5000)), 200),
            3 => http.StreamedResponse(Stream.value(audioFixture()), 403),
            _ => http.StreamedResponse(
              Stream.value(audioFixture()),
              200,
              contentLength: 2048,
            ),
          };
        }),
      );
      await manager.configure('one', api);
      await manager.enqueue([
        a,
        b,
        const Track(id: 'c', title: 'C'),
        const Track(id: 'd', title: 'D'),
      ]);
      await waitDownloads(manager);
      expect(manager.items.every((t) => t.state == DownloadState.failed), true);
      expect(
        await Directory('${directory.path}/downloaded_audio').list().toList(),
        isEmpty,
      );
      await manager.enqueue([a]);
      await waitDownloads(manager);
      expect(manager.forTrack(a.id)!.state, DownloadState.ready);
      expect(await manager.localPath('one', a.id), isNotNull);
      final rows = await store.db.query('downloads');
      expect(rows.toString(), isNot(contains('https://')));
      expect(rows.toString(), isNot(contains('test-credential')));
    },
  );

  test(
    'Cancel stalled URL resolution promptly and leave later jobs usable',
    () async {
      api.gate = Completer<String>();
      await manager.enqueue([a, b]);
      while (api.calls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await manager.cancel(b.id); // queued cancellation
      await manager.cancel(a.id).timeout(const Duration(seconds: 2));
      expect(manager.items, isEmpty);
      api.gate!.complete('https://audio.example/late');
      api.gate = null;
      await manager.enqueue([b]);
      await waitDownloads(manager);
      expect(manager.tracks.single.id, 'b');
    },
  );

  test(
    'Recovery cleans partial/orphan files and catches missing completed file',
    () async {
      await manager.enqueue([a, b]);
      await waitDownloads(manager);
      final missing = await manager.localPath('one', a.id);
      await File(missing!).delete();
      final root = Directory('${directory.path}/downloaded_audio');
      await File('${root.path}/abandoned.part').writeAsString('partial');
      await File('${root.path}/orphan.audio').writeAsString('orphan');
      await store.db.update(
        'downloads',
        {'state': 'downloading'},
        where: 'track=?',
        whereArgs: [b.id],
      );
      await manager.close();
      manager = DownloadManager(store);
      await manager.configure('one', null);
      expect(manager.items.every((t) => t.state == DownloadState.failed), true);
      expect(await root.list().toList(), isEmpty);
      expect(api.calls, 2); // no automatic network retry
    },
  );

  test(
    'Unsafe URLs and manifest file paths cannot escape private directory',
    () async {
      api.url = 'http://audio.example';
      await manager.enqueue([a]);
      await waitDownloads(manager);
      expect(manager.forTrack(a.id)!.state, DownloadState.failed);
      final outside = File('${directory.path}/protected');
      await outside.writeAsString('preserve');
      await store.db.update(
        'downloads',
        {'file': '../protected', 'state': 'ready', 'bytes': 8},
        where: 'track=?',
        whereArgs: [a.id],
      );
      expect(await manager.localPath('one', a.id), isNull);
      await manager.close();
      manager = DownloadManager(store);
      await manager.configure('one', null);
      expect(await outside.readAsString(), 'preserve');
      expect(manager.items, isEmpty);
    },
  );

  test(
    'Account switch cancels an active body and preserves retryable old jobs',
    () async {
      await manager.close();
      final body = StreamController<List<int>>();
      var cancelled = false;
      body.onCancel = () {
        cancelled = true;
      };
      manager = DownloadManager(
        store,
        clientFactory: () => MockClient.streaming(
          (request, bytes) async => http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'audio/wav'},
          ),
        ),
      );
      await manager.configure('one', api);
      await manager.enqueue([a, b]);
      body.add(audioFixture());
      while (manager.forTrack(a.id)?.bytes == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await manager.configure('two', null).timeout(const Duration(seconds: 2));
      expect(cancelled, true);
      expect(manager.items, isEmpty);
      expect(
        await Directory('${directory.path}/downloaded_audio').list().toList(),
        isEmpty,
      );
      await manager.configure('one', api);
      expect(
        manager.items.every((item) => item.state == DownloadState.failed),
        true,
      );
      expect(api.calls, 1);
      await body.close();
    },
  );

  test(
    'Disk-full failure stops the rest of a list and keeps retry controls',
    () async {
      await manager.close();
      var calls = 0;
      manager = DownloadManager(
        store,
        clientFactory: () => MockClient.streaming((request, body) async {
          calls++;
          return http.StreamedResponse(
            Stream.error(
              const FileSystemException(
                'fixture full',
                '',
                OSError('No space', 28),
              ),
            ),
            200,
            headers: {'content-type': 'audio/wav'},
          );
        }),
      );
      await manager.configure('one', api);
      await manager.enqueue([a, b]);
      await waitDownloads(manager);
      expect(calls, 1);
      expect(
        manager.items.every(
          (item) =>
              item.state == DownloadState.failed &&
              item.error!.contains('нет места'),
        ),
        true,
      );
    },
  );

  test('Version one upgrade preserves votes, state and queue', () async {
    await manager.close();
    await store.close();
    await factory.deleteDatabase('${directory.path}/test.db');
    final old = await factory.openDatabase(
      '${directory.path}/test.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE votes (account TEXT NOT NULL, id TEXT NOT NULL, track TEXT NOT NULL, delta INTEGER NOT NULL, created TEXT NOT NULL, undone INTEGER NOT NULL DEFAULT 0, metadata TEXT NOT NULL, PRIMARY KEY(account,id))',
          );
          await db.execute(
            'CREATE TABLE state (account TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(account,key))',
          );
        },
      ),
    );
    final legacy = LibraryStore(old);
    await legacy.vote('one', a, -1);
    await legacy.put('one', 'queue', {
      'tracks': [a.toJson()],
      'index': 0,
      'position': 1234,
    });
    await legacy.close();
    store = await LibraryStore.open(
      factory: factory,
      databasePath: '${directory.path}/test.db',
    );
    manager = DownloadManager(store);
    await manager.configure('one', api);
    expect((await store.ratings('one'))[a.id]!.score, 9);
    expect((await store.get('one', 'queue'))['position'], 1234);
    expect(await store.db.getVersion(), 2);
    await manager.enqueue([
      a,
    ]); // default HTTP cannot reach example; cancelled in teardown
  });
}
