import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/catalog_models.dart';

void main() {
  http.Response response(Object data) =>
      http.Response(jsonEncode({'data': data}), 200);
  test(
    'Saved catalog preserves order, batches and skips unavailable rows',
    () async {
      final requests = <List<dynamic>>[];
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final b = jsonDecode(req.body), v = b['variables'];
          if (b['operationName'] == 'savedCatalog') {
            return response({
              'collection': {
                'releases': [
                  {'id': 'r2'},
                  {'id': 'r1'},
                  {'id': 'missing'},
                ],
                'artists': List.generate(51, (i) => {'id': 'a$i'}),
              },
            });
          }
          requests.add(v['ids']);
          final album = (b['query'] as String).contains('getReleases');
          return response({
            album ? 'getReleases' : 'getArtists': [
              null,
              ...(v['ids'] as List).reversed
                  .where((id) => id != 'missing')
                  .map((id) => {'id': id, 'title': id}),
            ],
          });
        }),
      );
      final items = await api.savedCatalog();
      expect(items.take(2).map((i) => i.id), ['r2', 'r1']);
      expect(items.length, 53);
      expect(requests.map((r) => r.length), [3, 50, 1]);
      expect(
        CatalogItem.fromJson(items.first.toJson()).kind,
        CatalogKind.album,
      );
      api.close();
    },
  );
  test(
    'History offset counts episode/null rows and skips malformed timestamps',
    () async {
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final b = jsonDecode(req.body);
          expect(b['variables'], {'limit': 4, 'offset': 4});
          return response({
            'listeningHistory': [
              null,
              {
                'lastListeningDttm': '2026-10-03T00:00:00Z',
                'mediaContent': {'__typename': 'Episode'},
              },
              {
                'lastListeningDttm': 'invalid',
                'mediaContent': {'__typename': 'Track', 'id': 'bad'},
              },
              {
                'lastListeningDttm': '2026-10-03T01:00:00Z',
                'mediaContent': {
                  '__typename': 'Track',
                  'id': 't',
                  'title': 'Fixture',
                },
              },
            ],
          });
        }),
      );
      final page = await api.listeningHistory(offset: 4, limit: 4);
      expect(page.nextOffset, 8);
      expect(page.entries.single.track.id, 't');
      api.close();
    },
  );
  test(
    'Album/artist likes use release/artist enums and reject failed mutations',
    () async {
      final types = <String>[];
      var fail = false;
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final b = jsonDecode(req.body);
          types.add(b['variables']['type']);
          return response({
            'collection': {'addItem': fail ? false : null, 'removeItem': null},
          });
        }),
      );
      await api.setCollectionItem('r', liked: true, kind: CatalogKind.album);
      await api.setCollectionItem('a', liked: false, kind: CatalogKind.artist);
      expect(types, ['release', 'artist']);
      fail = true;
      await expectLater(
        api.setCollectionItem('a', liked: true, kind: CatalogKind.artist),
        throwsA(isA<ZvukException>()),
      );
      api.close();
    },
  );
  test('Lyrics support tiny wrapper and explicit missing text', () async {
    var empty = false;
    final api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        expect(req.url.queryParameters['track_id'], 't');
        return http.Response(
          jsonEncode({
            'result': {
              'lyrics': empty ? '' : '[00:01]Example',
              'type': 'subtitle',
            },
          }),
          200,
        );
      }),
    );
    expect((await api.lyrics('t'))!.synced, true);
    empty = true;
    expect(await api.lyrics('t'), isNull);
    api.close();
  });
}
