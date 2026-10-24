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
  List<Track> played = [];
  int playedIndex = -1;
  @override
  Future<void> playList(
    List<Track> tracks,
    int index, {
    String title = 'Очередь',
    bool shuffled = false,
  }) async {
    played = List.of(tracks);
    playedIndex = index;
  }

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
  late UnusedMusic music;
  const track = Track(id: 't', title: 'Track');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-collection-test');
    store = await LibraryStore.open(
      factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
    music = UnusedMusic();
    app = AppController(store, music)
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

  test(
    'Repeated votes preserve rows and playback until offline refresh',
    () async {
      const a = Track(id: 'a', title: 'A');
      const b = Track(id: 'b', title: 'B');
      app.tracks = app.favoriteTracks = [a, b];
      await store.saveTracks('owner', 'favorites', app.tracks);
      expect(app.visibleTracks.map((t) => t.id), ['a', 'b']);
      for (var i = 0; i < 5; i++) {
        await app.vote(b, 1);
        expect(app.visibleTracks.map((t) => t.id), ['a', 'b']);
      }
      expect(app.scoreFor(b), 14);
      expect(app.positionFor(b)!.label, '1');
      expect((await store.ratings('owner'))['b']!.score, 14);
      await app.playVisible(index: 1);
      expect(music.played.map((t) => t.id), ['a', 'b']);
      expect(music.played[music.playedIndex].id, 'b');
      await app.playVisible();
      expect(music.playedIndex, 0);
      expect(music.played.first.id, 'a');
      await app.refresh(); // Re-sorting works even without an API connection.
      expect(app.visibleTracks.map((t) => t.id), ['b', 'a']);
      for (var i = 0; i < 8; i++) {
        await app.vote(b, -1);
        expect(app.visibleTracks.map((t) => t.id), ['b', 'a']);
      }
      expect(app.scoreFor(b), 6);
      expect(app.positionFor(b)!.label, '2');
      await app.selectPlaylist(null);
      expect(app.visibleTracks.map((t) => t.id), ['a', 'b']);
      expect(await store.loadTracks('owner', 'favorites'), hasLength(2));
    },
  );

  test(
    'Slow refresh does not move a song voted on during synchronization',
    () async {
      const a = Track(id: 'a', title: 'A');
      const b = Track(id: 'b', title: 'B');
      await store.saveTracks('owner', 'favorites', [a]);
      await store.vote('owner', b, 1, addToLibrary: true);
      app.tracks = app.favoriteTracks = await store.loadTracks(
        'owner',
        'favorites',
      );
      app.ratings = await store.ratings('owner');
      expect(app.visibleTracks.map((t) => t.id), ['b', 'a']);
      final entered = Completer<void>(), release = Completer<void>();
      var synced = false;
      app.api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          switch (jsonDecode(req.body)['operationName']) {
            case 'changeCollection':
              entered.complete();
              await release.future;
              synced = true;
              return response({
                'collection': {'addItem': null},
              });
            case 'savedCatalog':
              return response({
                'collection': {'artists': [], 'releases': []},
              });
            case 'userCollection':
              return response({
                'collection': {
                  'tracks': [
                    {'id': 'a'},
                    if (synced) {'id': 'b'},
                  ],
                },
              });
            case 'getTracks':
              return response({
                'getTracks': [
                  {'id': 'a', 'title': 'A'},
                  {'id': 'b', 'title': 'B'},
                ],
              });
            case 'userPlaylists':
              return response({
                'collection': {'playlists': []},
              });
            default:
              throw StateError('Unexpected request');
          }
        }),
      );
      final refresh = app.refresh();
      await entered.future;
      await app.vote(b, -1);
      await app.vote(b, -1);
      expect(app.scoreFor(b), 8);
      expect(app.visibleTracks.map((t) => t.id), ['b', 'a']);
      release.complete();
      await refresh;
      expect(app.message, isNull);
      expect(app.visibleTracks.map((t) => t.id), ['b', 'a']);
      await app.refresh();
      expect(app.visibleTracks.map((t) => t.id), ['a', 'b']);
    },
  );

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

  test('Plus collects a new song at ten and synchronizes once', () async {
    var writes = 0;
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        if (jsonDecode(req.body)['operationName'] == 'userCollection') {
          return response({
            'collection': {'tracks': []},
          });
        }
        expect(jsonDecode(req.body)['operationName'], 'changeCollection');
        expect(jsonDecode(req.body)['query'], contains('addItem'));
        writes++;
        return response({
          'collection': {'addItem': null},
        });
      }),
    );
    expect(app.scoreFor(track), 9);
    await app.vote(track, 1);
    await app.syncLibraryAdds();
    expect(app.scoreFor(track), 10);
    expect(app.isFavorite(track.id), true);
    expect(app.visibleTracks.single.id, track.id);
    await app.vote(track, 1);
    await app.syncLibraryAdds();
    expect(app.scoreFor(track), 11);
    expect(writes, 1);
    for (var i = 0; i < 12; i++) {
      await app.vote(track, -1);
    }
    expect(app.scoreFor(track), -1);
    expect(app.isFavorite(track.id), true);
    expect(await store.pendingFavoriteAdds('owner'), isEmpty);
  });

  test(
    'Failed sync preserves local score, membership and pending addition',
    () async {
      app.api = ZvukApi(
        'fixture',
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      await app.vote(track, 1);
      await app.syncLibraryAdds();
      expect(app.scoreFor(track), 10);
      expect(app.isFavorite(track.id), true);
      expect(
        (await store.loadTracks('owner', 'favorites')).single.id,
        track.id,
      );
      expect(await store.pendingFavoriteAdds('owner'), hasLength(1));
      expect(app.serverBusy, false);
      app.api!.close();
      app.api = ZvukApi(
        'fixture',
        client: MockClient(
          (req) async => response({
            'collection':
                jsonDecode(req.body)['operationName'] == 'userCollection'
                ? {'tracks': []}
                : {'addItem': null},
          }),
        ),
      );
      await app.syncLibraryAdds();
      expect(await store.pendingFavoriteAdds('owner'), isEmpty);
      expect(app.scoreFor(track), 10);
    },
  );

  test(
    'A completion after account switch only acknowledges the old account',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final old = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          if (jsonDecode(req.body)['operationName'] == 'userCollection') {
            return response({
              'collection': {'tracks': []},
            });
          }
          entered.complete();
          await release.future;
          return response({
            'collection': {'addItem': null},
          });
        }),
      );
      app.api = old;
      await app.vote(track, 1);
      await entered.future;
      final done = app.syncLibraryAdds();
      const other = Track(id: 'other', title: 'Other');
      app.account = const Account('other', 'Other');
      app.api = ZvukApi(
        'other',
        client: MockClient(
          (_) async => throw StateError('Must not write to new account'),
        ),
      );
      app.tracks = [other];
      app.favoriteTracks = [other];
      app.ratings = {};
      release.complete();
      await done;
      expect(app.favoriteTracks.single.id, other.id);
      expect(await store.pendingFavoriteAdds('owner'), isEmpty);
      expect(
        (await store.loadTracks('owner', 'favorites')).single.id,
        track.id,
      );
      expect(await store.loadTracks('other', 'favorites'), isEmpty);
      expect(app.ratings, isEmpty);
      old.close();
    },
  );

  test('A stale remote read cannot remove a locally collected song', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var reads = 0;
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        switch (jsonDecode(req.body)['operationName']) {
          case 'userCollection':
            if (reads++ == 0) {
              entered.complete();
              await release.future;
            }
            return response({
              'collection': {'tracks': []},
            });
          case 'changeCollection':
            return http.Response('{}', 503);
          default:
            throw StateError('Unexpected request');
        }
      }),
    );
    final read = app.selectPlaylist(null);
    await entered.future;
    await app.vote(track, 1);
    await app.syncLibraryAdds();
    release.complete();
    await read;
    expect(app.isFavorite(track.id), true);
    expect(app.tracks.single.id, track.id);
    expect((await store.loadTracks('owner', 'favorites')).single.id, track.id);
    expect(app.scoreFor(track), 10);
  });

  test(
    'An existing remote favorite is acknowledged without adding again',
    () async {
      await store.vote('owner', track, 1, addToLibrary: true);
      app.api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          expect(jsonDecode(req.body)['operationName'], 'userCollection');
          return response({
            'collection': {
              'tracks': [
                {'id': track.id},
                {'id': track.id},
              ],
            },
          });
        }),
      );
      await app.syncLibraryAdds();
      expect(await store.pendingFavoriteAdds('owner'), isEmpty);
      expect(trackScore(track.id, await store.ratings('owner')), 10);
      expect(await store.loadTracks('owner', 'favorites'), hasLength(1));
    },
  );

  test('A lost write response is retried by reading membership, without a second add', () async {
    var remoteHasTrack = false, writes = 0;
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        switch (jsonDecode(req.body)['operationName']) {
          case 'userCollection':
            return response({
              'collection': {
                'tracks': [
                  if (remoteHasTrack) {'id': track.id},
                ],
              },
            });
          case 'changeCollection':
            writes++;
            remoteHasTrack = true;
            return http.Response('{}', 503);
          default:
            throw StateError('Unexpected request');
        }
      }),
    );
    await app.vote(track, 1);
    await app.syncLibraryAdds();
    expect(writes, 1);
    expect(await store.pendingFavoriteAdds('owner'), isEmpty);
    expect(app.scoreFor(track), 10);
    expect(app.favoriteTracks, hasLength(1));
  });
}
