import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  test('Every category uses its own field and opaque cursor', () async {
    for (final kind in CatalogKind.values) {
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final body = jsonDecode(req.body);
          expect(body['query'], contains('${kind.field}(limit:'));
          expect(body['variables']['cursor'], 'opaque');
          return http.Response(
            jsonEncode({
              'data': {
                'search': {
                  kind.field: {
                    'items': [
                      {
                        'id': '12',
                        'title': 'Item',
                        'artists': [
                          {'id': 'a', 'title': 'Artist'},
                        ],
                        'release': {'id': 'r'},
                      },
                    ],
                    'page': {'next': 30, 'cursor': 'new-opaque'},
                  },
                },
              },
            }),
            200,
          );
        }),
      );
      final page = await api.searchCatalog('song', kind, cursor: 'opaque');
      expect(page.next, 'new-opaque');
      if (kind == CatalogKind.track) {
        expect(page.tracks.single.artistIds, ['a']);
        expect(page.tracks.single.releaseId, 'r');
      } else {
        expect(page.items.single.kind, kind);
      }
      api.close();
    }
  });
  test(
    'Album hydrates all tracks; playlist caches ownership and privacy',
    () async {
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final body = jsonDecode(req.body);
          return http.Response(
            jsonEncode({
              'data': body['operationName'] == 'getPlaylists'
                  ? {
                      'getPlaylists': [
                        {
                          'id': 'p',
                          'title': 'List',
                          'userId': 42,
                          'isPublic': true,
                          'tracks': [
                            {'id': 't'},
                          ],
                        },
                      ],
                    }
                  : {
                      'getReleases': [
                        {
                          'id': 'r',
                          'title': 'Album',
                          'tracks': [
                            null,
                            ...List.generate(
                              120,
                              (i) => {'id': '$i', 'title': 'Track'},
                            ),
                          ],
                        },
                      ],
                    },
            }),
            200,
          );
        }),
      );
      final detail = await api.catalogDetail(
        const CatalogItem(id: 'r', title: '', kind: CatalogKind.album),
      );
      expect(detail.tracks, hasLength(120));
      final p = PlaylistInfo.fromJson(
        (await api.getPlaylists(['p'])).single.toJson(),
      );
      expect(p.ownerId, '42');
      expect(p.isPublic, true);
      expect(p.trackCount, 1);
      final old = PlaylistInfo.fromJson({'id': '1', 'title': 'Old'});
      expect(old.ownerId, isNull);
      api.close();
    },
  );
  test('Void null mutation succeeds; missing field and false fail', () async {
    for (final result in [
      {'rename': null},
      {'rename': false},
      <String, dynamic>{},
    ]) {
      final api = ZvukApi(
        'fixture',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {'playlist': result},
            }),
            200,
          ),
        ),
      );
      if (result.containsKey('rename') && result['rename'] == null) {
        await api.renamePlaylist('p', 'Name');
      } else {
        await expectLater(
          api.renamePlaylist('p', 'Name'),
          throwsA(isA<ZvukException>()),
        );
      }
      api.close();
    }
  });
  test(
    'Replacement preserves metadata and duplicate track occurrences',
    () async {
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final vars = jsonDecode(req.body)['variables'];
          expect(vars['isPublic'], true);
          expect(vars['name'], 'Keep name');
          expect(vars['items'], [
            {'type': 'track', 'item_id': 't'},
            {'type': 'track', 'item_id': 't'},
          ]);
          return http.Response('{"data":{"playlist":{"update":null}}}', 200);
        }),
      );
      await api.replacePlaylistTracks(
        const PlaylistInfo('p', 'Keep name', isPublic: true),
        ['t', 't'],
      );
      api.close();
    },
  );
  test('Create keeps an empty list public only until privacy is set; failure rolls it back', () async {
    for (final failPrivacy in [false, true]) {
      final calls = <String>[];
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final b = jsonDecode(req.body), name = b['operationName'] as String;
          calls.add(name);
          if (name == 'createPlayList') {
            expect(b['variables']['items'], isEmpty);
            return http.Response('{"data":{"playlist":{"create":"new"}}}', 200);
          }
          if (name == 'setPlaylistToPublic') {
            expect(b['variables']['isPublic'], false);
            return http.Response(
              jsonEncode({
                'data': {
                  'playlist': {'setPublic': failPrivacy ? false : null},
                },
              }),
              200,
            );
          }
          if (name == 'deletePlaylist') {
            expect(b['variables']['id'], 'new');
            return http.Response('{"data":{"playlist":{"delete":null}}}', 200);
          }
          expect(name, 'addTracksToPlaylist');
          return http.Response('{"data":{"playlist":{"addItems":null}}}', 200);
        }),
      );
      if (failPrivacy) {
        await expectLater(
          api.createPlaylist('New', trackIds: ['t']),
          throwsA(isA<ZvukException>()),
        );
        expect(calls, [
          'createPlayList',
          'setPlaylistToPublic',
          'deletePlaylist',
        ]);
      } else {
        expect(await api.createPlaylist('New', trackIds: ['t']), 'new');
        expect(calls, [
          'createPlayList',
          'setPlaylistToPublic',
          'addTracksToPlaylist',
        ]);
      }
      api.close();
    }
  });
}
