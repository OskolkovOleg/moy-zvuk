import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/search_history_store.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/search_controller.dart';

Map<String, dynamic> song(String id) => {
  '__typename': 'Track',
  'id': id,
  'title': id,
};
http.Response quick(List<dynamic> content) => http.Response(
  jsonEncode({
    'data': {
      'quickSearch': {'content': content},
    },
  }),
  200,
);
http.Response page(List<String> ids, String? cursor) => http.Response(
  jsonEncode({
    'data': {
      'search': {
        'tracks': {
          'items': ids.map(song).toList(),
          'page': {'next': cursor == null ? null : 30, 'cursor': cursor},
        },
      },
    },
  }),
  200,
);

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-search-test');
    store = await LibraryStore.open(
      factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('Quick search preserves mixed ranking and ignores unsupported/duplicate hits', () async {
    final api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final b = jsonDecode(req.body);
        expect(b['operationName'], 'quickSearch');
        expect(b['variables'], {'query': 'музыка', 'limit': 12});
        return quick([
          {'__typename': 'Artist', 'id': '1', 'title': 'Artist'},
          song('1'),
          null,
          song('1'),
          {'__typename': 'Release', 'id': '2', 'title': 'Album'},
          {'__typename': 'Playlist', 'id': '3', 'title': 'List'},
          {'__typename': 'Podcast', 'id': '4', 'title': 'Podcast'},
          {'__typename': 'Track', 'title': 'No ID'},
        ]);
      }),
    );
    expect((await api.quickSearch(' музыка ')).map((h) => h.key), [
      'artist:1',
      'track:1',
      'album:2',
      'playlist:3',
    ]);
    api.close();
  });

  test('Valid empty results differ from unavailable search', () async {
    for (final body in [
      '{"data":{"quickSearch":{"content":[]}}}',
      '{"data":{"quickSearch":null}}',
      '{"errors":[{"message":"error"}]}',
    ]) {
      final api = ZvukApi(
        'fixture',
        client: MockClient((_) async => http.Response(body, 200)),
      );
      if (body.contains('content')) {
        expect(await api.quickSearch('aa'), isEmpty);
      } else {
        await expectLater(api.quickSearch('aa'), throwsA(isA<ZvukException>()));
      }
      api.close();
    }
  });

  test(
    'Search history is concurrent, normalized, bounded, durable and isolated',
    () async {
      var history = SearchHistoryStore(store);
      await Future.wait(
        List.generate(25, (i) => history.record('a', 'query $i')),
      );
      expect(await history.recent('a'), hasLength(20));
      await history.record('a', '  QUERY   7  ');
      expect((await history.recent('a')).first, 'QUERY 7');
      expect(
        (await history.recent('a')).where((q) => q.toLowerCase() == 'query 7'),
        hasLength(1),
      );
      await history.record('b', 'Other');
      await store.close();
      store = await LibraryStore.open(
        factory: Platform.isAndroid
            ? native.databaseFactory
            : databaseFactoryFfi,
        databasePath: '${directory.path}/test.db',
      );
      history = SearchHistoryStore(store);
      expect((await history.recent('a')).first, 'QUERY 7');
      await history.remove('a', 'query 7');
      expect((await history.recent('a')).contains('QUERY 7'), false);
      await history.clear('a');
      expect(await history.recent('a'), isEmpty);
      expect(await history.recent('b'), ['Other']);
    },
  );

  test('Typing debounces without recording fragments; clearing cancels pending work', () async {
    final calls = <String>[];
    final api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        calls.add(jsonDecode(req.body)['variables']['query'] as String);
        return quick([song(calls.last)]);
      }),
    );
    final c = MusicSearchController(
      api,
      SearchHistoryStore(store),
      'a',
      debounce: const Duration(milliseconds: 20),
    );
    c.edit('б');
    c.edit('би');
    c.edit('билли');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, ['билли']);
    expect(await c.history.recent('a'), isEmpty);
    c.edit('clear');
    c.edit('');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, ['билли']);
    expect(c.hits, isEmpty);
    expect(c.busy, false);
    await c.submit('я');
    await c.initialize();
    expect(calls, ['билли', 'я']);
    expect(c.recent, ['я']);
    c.dispose();
    api.close();
  });

  test('Old success and failure cannot replace a new query, clear or disposed screen', () async {
    final pending = <Completer<http.Response>>[];
    final api = ZvukApi(
      'fixture',
      client: MockClient((_) {
        final hold = Completer<http.Response>();
        pending.add(hold);
        return hold.future;
      }),
    );
    final c = MusicSearchController(api, SearchHistoryStore(store), 'a');
    Future<void> waitRequests(int count) async {
      for (var i = 0; i < 100 && pending.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(pending, hasLength(count));
    }

    final old = c.submit('old');
    await waitRequests(1);
    c.edit('new');
    pending[0].complete(quick([song('stale')]));
    await old;
    expect(c.hits, isEmpty);
    expect(c.busy, true);
    final fresh = c.submit('new');
    await waitRequests(2);
    pending[1].complete(quick([song('fresh')]));
    await fresh;
    expect(c.hits.single.key, 'track:fresh');
    final clear = c.submit('clear');
    await waitRequests(3);
    c.edit('');
    pending[2].complete(http.Response('{}', 503));
    await clear;
    expect(c.error, isEmpty);
    expect(c.busy, false);
    expect(c.hits, isEmpty);
    final last = c.submit('disposed');
    await waitRequests(4);
    c.dispose();
    pending[3].complete(quick([song('late')]));
    await last;
    await c.history.recent('a');
    api.close();
  });

  test('Category change rejects stale response and paging deduplicates and retries', () async {
    final held = Completer<http.Response>();
    final reached = Completer<void>();
    var failMore = true, pageCalls = 0;
    final api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final body = jsonDecode(req.body);
        if (body['operationName'] == 'quickSearch') {
          reached.complete();
          return held.future;
        }
        pageCalls++;
        final cursor = body['variables']['cursor'];
        if (cursor == null) return page(['1', '2'], 'opaque');
        expect(cursor, 'opaque');
        if (failMore) return http.Response('{}', 503);
        return page(['2', '3'], 'opaque');
      }),
    );
    final c = MusicSearchController(api, SearchHistoryStore(store), 'a');
    final old = c.submit('same');
    await reached.future;
    await c.choose(CatalogKind.track);
    held.complete(quick([song('wrong')]));
    await old;
    expect(c.hits.map((h) => h.key), ['track:1', 'track:2']);
    await c.loadMore();
    expect(c.error, isNotEmpty);
    expect(c.hits, hasLength(2));
    failMore = false;
    await c.retry();
    expect(c.hits.map((h) => h.key), ['track:1', 'track:2', 'track:3']);
    expect(c.next, isNull);
    expect(c.error, isEmpty);
    await c.loadMore();
    expect(pageCalls, 3);
    c.dispose();
    api.close();
  });
}
