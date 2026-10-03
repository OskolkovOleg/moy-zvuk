// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/history_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/catalog_widgets.dart';
import 'package:zvuk_personal/ui/lyrics_screen.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';

import 'background_controls_test.dart' show silence, until;

class PersonalFixtureApi extends ZvukApi {
  PersonalFixtureApi(this.port, http.Client client)
    : super('fixture', client: client);
  final int port;
  @override
  Future<String> streamUrl(
    String id, {
    AudioQuality quality = AudioQuality.high,
  }) async {
    if (id == 'broken') throw const ZvukException('Synthetic failure');
    return 'http://127.0.0.1:$port/$id.wav';
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Personal collection, lyrics seeking, local/server history and narrow screens',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('zvuk-personal-ui');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.add(silence(60));
        await request.response.close();
      });
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      final song = <String, dynamic>{
        'id': 't',
        'title': 'Ночная дорога',
        'duration': 60,
        'artists': [
          {'id': 'a', 'title': 'Тестовый артист'},
        ],
        'release': {'id': 'r'},
      };
      var saved = true, historyCalls = 0;
      final api = PersonalFixtureApi(
        server.port,
        MockClient((req) async {
          dynamic data;
          if (req.url.path.endsWith('/lyrics')) {
            return http.Response(
              jsonEncode({
                'result': {
                  'type': 'subtitle',
                  'lyrics': '[00:00]Первая тестовая строка\n[00:10]Вторая тестовая строка\n[00:20]Третья тестовая строка',
                  'translation': 'Тестовый перевод',
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final b = jsonDecode(req.body), q = b['query'] as String;
          switch (b['operationName']) {
            case 'savedCatalog':
              data = {
                'collection': {
                  'artists': [
                    {'id': 'a'},
                  ],
                  'releases': saved
                      ? [
                          {'id': 'r'},
                        ]
                      : [],
                },
              };
            case 'savedMetadata':
              data = q.contains('getReleases')
                  ? {
                      'getReleases': [
                        {
                          'id': 'r',
                          'title': 'Сохранённый альбом',
                          'artists': [
                            {'title': 'Тестовый артист'},
                          ],
                        },
                      ],
                    }
                  : {
                      'getArtists': [
                        {'id': 'a', 'title': 'Тестовый артист'},
                      ],
                    };
            case 'catalogDetail':
              data = q.contains('getArtists')
                  ? {
                      'getArtists': [
                        {
                          'id': 'a',
                          'title': 'Тестовый артист',
                          'popularTracks': [song],
                        },
                      ],
                    }
                  : {
                      'getReleases': [
                        {
                          'id': 'r',
                          'title': 'Сохранённый альбом',
                          'tracks': [song],
                        },
                      ],
                    };
            case 'changeCollection':
              saved = q.contains('addItem');
              data = {
                'collection': {saved ? 'addItem' : 'removeItem': null},
              };
            case 'recentHistory':
              historyCalls++;
              data = {
                'listeningHistory': [
                  {
                    'lastListeningDttm': '2026-10-03T01:00:00Z',
                    'mediaContent': {'__typename': 'Track', ...song},
                  },
                ],
              };
            default:
              return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode({'data': data}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final app = AppController(store, music)
        ..account = const Account('fixture', 'Тест')
        ..api = api
        ..tracks = [Track.fromApi(song)];
      final history = HistoryStore(store);
      Future<void> back() async {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      try {
        await music.initialize();
        await music.configure('fixture', api);
        await music.player.setVolume(0);
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('v150-01-library');
        await tester.tap(find.widgetWithText(ActionChip, 'Альбомы'));
        await tester.pumpAndSettle();
        expect(find.text('Сохранённый альбом'), findsOneWidget);
        await binding.takeScreenshot('v150-02-albums');
        await tester.tap(find.byType(CatalogTile));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сохранено'));
        await tester.pumpAndSettle();
        expect(saved, false);
        expect(find.text('Сохранить'), findsOneWidget);
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(saved, true);
        await back();
        await back();
        await tester.tap(find.widgetWithText(ActionChip, 'Артисты'));
        await tester.pumpAndSettle();
        expect(find.text('Тестовый артист'), findsOneWidget);
        await back();
        await music.playList([Track.fromApi(song)], 0);
        await until(() => music.player.position.inMilliseconds > 150);
        await music.pause();
        await tester.pumpAndSettle();
        var recent = await history.recent('fixture');
        expect(recent.single.track.id, 't');
        final recorded = recent.single.at;
        await music.play();
        await until(() => music.player.playing);
        await music.pause();
        expect((await history.recent('fixture')).single.at, recorded);
        await music.enqueueTrack(const Track(id: 'queued', title: 'Queued'));
        expect((await history.recent('fixture')).length, 1);
        await tester.ensureVisible(find.widgetWithText(ActionChip, 'История'));
        await tester.tap(find.widgetWithText(ActionChip, 'История'));
        await tester.pumpAndSettle();
        expect(find.text('Ночная дорога'), findsNWidgets(2));
        await binding.takeScreenshot('v150-03-history');
        await tester.tap(find.text('В Звуке'));
        await tester.pumpAndSettle();
        expect(historyCalls, 1);
        await back();
        final context = tester.element(find.byType(MiniPlayer).first);
        openLyrics(context, app, Track.fromApi(song));
        await tester.pumpAndSettle();
        expect(find.text('Первая тестовая строка'), findsOneWidget);
        await tester.tap(find.text('Вторая тестовая строка'));
        await tester.pumpAndSettle();
        expect(music.position.inSeconds, 10);
        await binding.takeScreenshot('v150-04-lyrics');
        await tester.tap(find.text('Перевод'));
        await tester.pumpAndSettle();
        expect(find.text('Тестовый перевод'), findsOneWidget);
        await tester.tap(find.text('Перевод'));
        await tester.pumpAndSettle();
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v150-05-lyrics-large');
        expect(tester.takeException(), isNull);
        await music.playList(const [Track(id: 'other', title: 'Other')], 0);
        await until(() => music.player.playing);
        await music.pause();
        await tester.pumpAndSettle();
        final beforeSeek = music.position;
        await tester.ensureVisible(find.text('Вторая тестовая строка'));
        await tester.tap(find.text('Вторая тестовая строка'));
        await tester.pumpAndSettle();
        expect(music.position, beforeSeek);

        await back();
        await tester.ensureVisible(find.widgetWithText(ActionChip, 'История'));
        await tester.tap(find.widgetWithText(ActionChip, 'История'));
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v150-06-history-large');
        expect(tester.takeException(), isNull);
        await back();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await music.playList(const [Track(id: 'broken', title: 'Broken')], 0);
        expect((await history.recent('fixture')).length, 2);
        await music.configure('another', api);
        expect(await history.recent('another'), isEmpty);
        print(
          'PERSONAL UI: saved collection, lyrics/seek/translation, local/server history, 1.6x typography: passed',
        );
        print(
          'HISTORY playback: ready start only, pause/resume stable, queue/failure ignored, account isolation: passed',
        );
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
