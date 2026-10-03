import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';

class UnusedMusic implements MusicHandler {
  @override
  Future<void> Function(String account, Track track, int delta)?
  onNotificationVote;

  @override
  void setNotificationRatings(String account, Map<String, Rating> ratings) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  late AppController app;
  const track = Track(id: 't', title: 'Track');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-collection-test');
    store = await LibraryStore.open(
      factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
    app = AppController(store, UnusedMusic())
      ..account = const Account('owner', 'Owner');
  });
  tearDown(() async {
    app.api?.close();
    app.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  http.Response response(Object value) =>
      http.Response(jsonEncode({'data': value}), 200);
  test('Refuses another owner and stale snapshots before mutation', () async {
    var writes = 0;
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        if (jsonDecode(req.body)['operationName'] == 'setPlaylistToPublic') {
          return response({
            'playlist': {'setPublic': null},
          });
        }
        final name = jsonDecode(req.body)['operationName'];
        if (name == 'getPlaylists') {
          return response({
            'getPlaylists': [
              {'id': 'p', 'title': 'Playlist', 'userId': 'someone-else'},
            ],
          });
        }
        if (name == 'getPlaylistTracks') {
          return response({
            'playlistTracks': [
              {'id': 'new', 'title': 'Changed'},
            ],
          });
        }
        writes++;
        return response({});
      }),
    );
    const p = PlaylistInfo('p', 'Playlist', ownerId: 'owner');
    await expectLater(
      app.renamePlaylist(p, 'Name'),
      throwsA(isA<ZvukException>()),
    );
    await expectLater(
      app.removeFromPlaylist(p, [track], 0),
      throwsA(isA<ZvukException>()),
    );
    expect(writes, 0);
  });
  test(
    'Removes one occurrence and preserves fresh name and visibility',
    () async {
      var replaced = false;
      app.api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          if (jsonDecode(req.body)['operationName'] == 'setPlaylistToPublic') {
            return response({
              'playlist': {'setPublic': null},
            });
          }
          final b = jsonDecode(req.body);
          switch (b['operationName']) {
            case 'getPlaylists':
              return response({
                'getPlaylists': [
                  {
                    'id': 'p',
                    'title': 'Fresh name',
                    'userId': 'owner',
                    'isPublic': true,
                  },
                ],
              });
            case 'getPlaylistTracks':
              return response({
                'playlistTracks': List.generate(
                  replaced ? 1 : 2,
                  (_) => {'id': 't', 'title': 'Track'},
                ),
              });
            case 'userPlaylists':
              return response({
                'collection': {
                  'playlists': [
                    {'id': 'p'},
                  ],
                },
              });
            case 'updataPlaylist':
              expect(b['variables']['name'], 'Fresh name');
              expect(b['variables']['isPublic'], true);
              expect(b['variables']['items'], [
                {'type': 'track', 'item_id': 't'},
              ]);
              replaced = true;
              return response({
                'playlist': {'update': null},
              });
            default:
              throw StateError('Unexpected operation');
          }
        }),
      );
      await app.removeFromPlaylist(
        const PlaylistInfo('p', 'Old name', ownerId: 'owner'),
        [track, track],
        0,
      );
      expect(replaced, true);
      expect(await store.loadTracks('owner', 'p'), hasLength(1));
    },
  );
  test('Committed create stays successful if readback fails', () async {
    var creates = 0;
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        if (jsonDecode(req.body)['operationName'] == 'setPlaylistToPublic') {
          return response({
            'playlist': {'setPublic': null},
          });
        }
        if (jsonDecode(req.body)['operationName'] == 'createPlayList') {
          creates++;
          return response({
            'playlist': {'create': 'new'},
          });
        }
        return http.Response('{}', 503);
      }),
    );
    final p = await app.createPlaylist('New');
    expect(p.id, 'new');
    expect(creates, 1);
    expect(app.playlists.single.id, 'new');
    expect(app.serverBusy, false);
  });
  test(
    'Queued edits serialize and reject a replaced account connection',
    () async {
      final release = Completer<void>(), entered = Completer<void>();
      var creates = 0;
      final old = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          if (jsonDecode(req.body)['operationName'] == 'setPlaylistToPublic') {
            return response({
              'playlist': {'setPublic': null},
            });
          }
          if (jsonDecode(req.body)['operationName'] == 'createPlayList') {
            creates++;
            entered.complete();
            await release.future;
            return response({
              'playlist': {'create': 'first'},
            });
          }
          return response({
            'collection': {'playlists': []},
          });
        }),
      );
      app.api = old;
      final first = app.createPlaylist('First');
      await entered.future;
      final second = app.createPlaylist('Second');
      final rejected = expectLater(second, throwsA(isA<ZvukException>()));
      app.api = ZvukApi(
        'other',
        client: MockClient((_) async => throw StateError('Must not call')),
      );
      app.account = const Account('other', 'Other');
      release.complete();
      await first;
      await rejected;
      expect(creates, 1);
      expect(app.playlists, isEmpty);
      old.close();
    },
  );
  test(
    'Favorite change preserves local votes and changes membership only',
    () async {
      for (var i = 0; i < 3; i++) {
        await app.vote(track, -1);
      }
      app.api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          if (jsonDecode(req.body)['operationName'] == 'setPlaylistToPublic') {
            return response({
              'playlist': {'setPublic': null},
            });
          }
          if (jsonDecode(req.body)['operationName'] == 'changeCollection') {
            return response({
              'collection': {'addItem': null},
            });
          }
          if (jsonDecode(req.body)['operationName'] == 'setPlaylistToPublic') {
            return response({
              'playlist': {'setPublic': null},
            });
          }
          return http.Response('{}', 503);
        }),
      );
      await app.setFavorite(track, true);
      expect(app.isFavorite('t'), true);
      expect(app.scoreFor(track), 7);
      expect(app.tracks.single.id, 't');
    },
  );
}
