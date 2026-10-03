// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/wave_source.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/catalog_widgets.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';
import 'package:zvuk_personal/ui/track_actions.dart';

import 'background_controls_test.dart' show silence;
import 'radio_playback_test.dart' show RadioFixtureApi;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Radio menus, catalog sources, favorites, cancellation and errors',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('zvuk-radio-ui');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.headers.contentType = ContentType('audio', 'wav');
        r.response.add(silence(20));
        await r.response.close();
      });
      Completer<void>? hold;
      var failRequest = false, calls = 0;
      final song = {
        'id': '7',
        'title': 'Ночная дорога',
        'duration': 20,
        'artists': [
          {'id': '11', 'title': 'Тестовый артист'},
        ],
        'release': {'id': '12'},
      };
      final api = RadioFixtureApi(
        server.port,
        'fixture',
        client: MockClient((req) async {
          if (req.url.path.contains('/grid/')) {
            return http.Response('{"result":{"page":{"data":[]}}}', 200);
          }
          final b = jsonDecode(req.body), v = b['variables'] as Map;
          Map<String, dynamic> d;
          switch (b['operationName']) {
            case 'contextRadio':
            case 'getPersonalWave':
              final batch = calls++;
              final wait = hold;
              if (wait != null) await wait.future;
              if (failRequest) return http.Response('{}', 503);
              final tracks = List.generate(
                6,
                (i) => {
                  ...song,
                  'id': 'long-$batch-$i',
                  'title': 'Похожая песня ${i + 1}',
                },
              );
              d = b['operationName'] == 'contextRadio'
                  ? {
                      'recommenderRadio': {'tracks': tracks, 'cursor': 6},
                    }
                  : {'personalWaveContent': tracks};
            case 'savedCatalog':
              d = {
                'collection': {'artists': [], 'releases': []},
              };
            case 'catalogDetail':
              final artist = (b['query'] as String).contains('getArtists');
              d = {
                artist ? 'getArtists' : 'getReleases': [
                  {
                    'id': v['ids'][0],
                    'title': artist ? 'Тестовый артист' : 'Вечерний альбом',
                    'popularTracks': [song],
                    'tracks': [song],
                    'releases': [],
                  },
                ],
              };
            case 'getPlaylists':
              d = {
                'getPlaylists': (v['ids'] as List)
                    .map(
                      (id) => {
                        'id': id,
                        'title': 'Вечерний плейлист',
                        'userId': 'fixture',
                        'tracks': [song],
                      },
                    )
                    .toList(),
              };
            case 'getPlaylistTracks':
              d = {
                'playlistTracks': [song],
              };
            default:
              return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode({'data': d}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      const track = Track(
        id: '7',
        title: 'Ночная дорога',
        artists: 'Тестовый артист',
        duration: 20,
        artistIds: ['11'],
        releaseId: '12',
      );
      final app = AppController(store, music)
        ..account = const Account('fixture', 'Тест')
        ..api = api
        ..tracks = [track];
      Future<void> ready() async {
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Подбираем поток').evaluate().isEmpty &&
              find.text('Похожие песни в очередь').evaluate().isEmpty) {
            await tester.pumpAndSettle();
            return;
          }
        }
        fail('Radio action did not close');
      }

      Future<void> tap(String text) async {
        await tester.ensureVisible(find.text(text).first);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text(text).first);
        await tester.pump();
      }

      BuildContext context() => tester.element(find.byType(MiniPlayer).first);
      try {
        await music.initialize();
        await music.configure('fixture', api);
        await music.player.setVolume(0);
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        openTrackActions(context(), app, track);
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('v170-01-track-actions');
        await tap('Добавить похожие в очередь');
        await ready();
        expect(music.playlist.length, 6);
        expect(music.player.playing, false);
        openTrackActions(context(), app, track);
        await tester.pumpAndSettle();
        await tap('Поток по песне');
        await ready();
        expect(music.waveSource.kind, WaveKind.track);
        expect(music.waveSource.id, '7');
        await music.pause();
        for (final kind in [
          CatalogKind.artist,
          CatalogKind.album,
          CatalogKind.playlist,
        ]) {
          openCatalog(
            context(),
            app,
            CatalogItem(
              id: kind == CatalogKind.playlist
                  ? '42'
                  : kind == CatalogKind.artist
                  ? '11'
                  : '12',
              title: 'Каталог',
              kind: kind,
            ),
          );
          await tester.pumpAndSettle();
          if (kind == CatalogKind.artist) {
            await binding.takeScreenshot('v170-02-artist');
          }
          await tap('Слушать похожее');
          await ready();
          expect(music.waveSource.kind.name, kind.name);
          await music.pause();
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await tap('Обзор');
        await tester.pumpAndSettle();
        await tap('Поток по любимому');
        await ready();
        expect(music.waveSource.kind, WaveKind.favorites);
        await music.pause();
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v170-03-discover-large');
        expect(tester.takeException(), isNull);
        hold = Completer<void>();
        final before = calls;
        await tap('Поток по любимому');
        for (var i = 0; i < 40 && calls == before; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(calls, greaterThan(before));
        await binding.takeScreenshot('v170-04-loading-large');
        await tap('Отмена');
        await tester.pumpAndSettle();
        hold.complete();
        hold = null;
        await tester.pump(const Duration(seconds: 1));
        expect(music.player.playing, false);
        expect(music.isWave, false);
        failRequest = true;
        await tap('Поток по любимому');
        for (
          var i = 0;
          i < 40 && find.text('Повторить').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Повторить'), findsOneWidget);
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v170-05-error-large');
        failRequest = false;
        await tap('Повторить');
        await ready();
        expect(music.isWave, true);
        await music.pause();
        expect(tester.takeException(), isNull);
        print(
          'RADIO UI track append/play, all catalog sources, favorites, large text, cancel and retry: passed',
        );
      } finally {
        if (hold != null && !hold.isCompleted) hold.complete();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
        await music.disposeHandler();
        app.dispose();
        api.close();
        await server.close(force: true);
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
