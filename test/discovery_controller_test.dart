import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/discovery_models.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/discovery_controller.dart';

import 'collection_controller_test.dart' show UnusedMusic;

http.Response reply(Object value) =>
    http.Response(jsonEncode({'data': value}), 200);
Map<String, Object> row(String id, {String artist = 'a'}) => {
  'id': id,
  'title': id,
  'explicit': false,
  'artists': [
    {'id': artist, 'title': artist},
  ],
};
void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  late AppController app;
  final controllers = <DiscoveryController>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('discovery-controller');
    store = await LibraryStore.open(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
    app = AppController(store, UnusedMusic())
      ..account = const Account('owner', 'Fixture');
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    app.api?.close();
    app.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  DiscoveryController controller(DiscoveryMode mode, {Track? seed}) {
    final c = DiscoveryController(
      app,
      mode,
      seed: seed,
      now: () => DateTime.utc(2026, 11, 6),
    );
    controllers.add(c);
    return c;
  }

  test('Best mode mixes real seeds, tolerates one failed source, persists cursor and never plays', () async {
    app.favoriteTracks = [
      const Track(id: '1', title: 'One', artistIds: ['one']),
      const Track(id: '2', title: 'Two', artistIds: ['two']),
    ];
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final b = jsonDecode(req.body);
        expect(b['operationName'], 'contextRadio');
        if (b['variables']['id'] == '2') return http.Response('{}', 500);
        return reply({
          'recommenderRadio': {
            'cursor': 50,
            'tracks': [row('new'), row('1')],
          },
        });
      }),
    );
    final c = controller(DiscoveryMode.best);
    await c.load();
    expect(c.candidates.single.track.id, 'new');
    expect(c.candidates.single.reason, contains('One'));
    expect(c.note, isNotNull);
    expect(c.error, null);
    expect((await c.memory.load('owner')).cursors['1'], 50);
    expect((app.music as UnusedMusic).played, isEmpty);
    expect(await store.loadTracks('owner', 'favorites'), isEmpty);
    await c.load();
    expect(c.candidates, isEmpty);
  });
  test('Explore uses only selected playlist sources; local ratings never choose genre tracks', () async {
    var personalized = false;
    app.ratings = {'irrelevant': const Rating(999, 990)};
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final b = jsonDecode(req.body);
        if (b['operationName'] == 'getPlaylists') {
          expect(b['variables']['ids'], ['8404268']);
          return reply({
            'getPlaylists': [
              {'id': '8404268', 'title': 'Club from service'},
            ],
          });
        }
        if (b['operationName'] != 'getPlaylistTracks') personalized = true;
        return reply({
          'playlistTracks': [row('club')],
        });
      }),
    );
    final c = controller(DiscoveryMode.explore)..direction = 'club';
    await c.load();
    expect(personalized, false);
    expect(c.candidates.single.reason, 'Club from service');
    expect(c.candidates.single.source!.kind, CatalogKind.playlist);
  });
  test('Real release dates filter old/future/unknown rows and retain album provenance', () async {
    app.savedCatalogItems = [
      const CatalogItem(
        id: 'artist',
        title: 'Artist',
        kind: CatalogKind.artist,
      ),
    ];
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final b = jsonDecode(req.body);
        expect(b['operationName'], 'discoveryReleases');
        expect(b['query'], contains('date'));
        expect(b['query'], contains('canonicalTrackId'));
        return reply({
          'getArtists': [
            null,
            {
              'id': 'artist',
              'releases': [
                null,
                for (final pair in [
                  ('fresh', '2026-10-30'),
                  ('old', '2026-01-01'),
                  ('future', '2027-01-01'),
                  ('unknown', 'invalid'),
                ])
                  {
                    'id': pair.$1,
                    'title': pair.$1,
                    'date': pair.$2,
                    'tracks': [null, row(pair.$1)],
                  },
              ],
            },
          ],
        });
      }),
    );
    final c = controller(DiscoveryMode.releases);
    await c.load();
    expect(c.candidates.single.track.id, 'fresh');
    expect(c.candidates.single.reason, '30.10.2026 · fresh');
    expect(c.candidates.single.source!.kind, CatalogKind.album);
  });
  test('Slow old seed request and changed accounts cannot overwrite current results', () async {
    final slow = Completer<http.Response>();
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final b = jsonDecode(req.body);
        if (b['variables']['id'] == 'old') return slow.future;
        return reply({
          'recommenderRadio': {
            'cursor': 50,
            'tracks': [row('correct')],
          },
        });
      }),
    );
    final c = controller(
      DiscoveryMode.song,
      seed: const Track(id: 'old', title: 'Old'),
    );
    final first = c.load();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    c.seed = const Track(id: 'new', title: 'New');
    await c.load();
    slow.complete(
      reply({
        'recommenderRadio': {
          'tracks': [row('wrong')],
          'cursor': 50,
        },
      }),
    );
    await first;
    expect(c.candidates.single.track.id, 'correct');
    app.account = const Account('another', 'Another');
    expect((await c.memory.load('another')).offered, isEmpty);
  });
  test('Hiding is separate from scores, excludes canonical variants and is reversible', () async {
    final c = controller(DiscoveryMode.song);
    const t = Track(id: 't', title: 'T', canonicalTrackId: 'master');
    c.candidates = [const DiscoveryCandidate(t, 'fixture')];
    await c.hide(t);
    expect(c.candidates, isEmpty);
    expect((await c.memory.load('owner')).hidden.single.id, 't');
    expect(await store.ratings('owner'), isEmpty);
    await c.memory.restore('owner', t);
    expect((await c.memory.load('owner')).hidden, isEmpty);
  });
  test(
    'Account switch during a request clears old results and stops loading',
    () async {
      final delayed = Completer<http.Response>();
      app.api = ZvukApi('fixture', client: MockClient((_) => delayed.future));
      final c = controller(
        DiscoveryMode.song,
        seed: const Track(id: 'old', title: 'Old'),
      );
      final pending = c.load();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      app.account = const Account('other', 'Other');
      delayed.complete(
        reply({
          'recommenderRadio': {
            'tracks': [row('private')],
            'cursor': 50,
          },
        }),
      );
      await pending;
      expect(c.candidates, isEmpty);
      expect(c.loading, false);
      expect(c.error, contains('Подключение изменилось'));
      expect((await c.memory.load('other')).offered, isEmpty);
    },
  );
}
