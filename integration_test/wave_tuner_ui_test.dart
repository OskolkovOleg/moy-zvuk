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
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/wave_options.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/artist_navigation.dart';
import 'package:zvuk_personal/ui/catalog_detail_screen.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';

import 'background_controls_test.dart' show silence, until;
import 'radio_playback_test.dart' show RadioFixtureApi;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Artist links and wave settings at narrow width and large text', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('wave-tuner-ui');
    final store = await LibraryStore.open(databasePath: '${dir.path}/test.db');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response.headers.contentType = ContentType('audio', 'wav');
      r.response.add(silence(60));
      await r.response.close();
    });
    var metadataReads = 0;
    final opened = <String>[];
    final song = {
      'id': '7',
      'title': 'Ночная дорога',
      'duration': 60,
      'artists': [
        {'id': '11', 'title': 'Тестовый артист'},
      ],
      'release': {'id': '12'},
    };
    final api = RadioFixtureApi(
      server.port,
      'fixture',
      client: MockClient((r) async {
        if (r.url.path.contains('/grid/')) {
          return http.Response('{"result":{"page":{"data":[]}}}', 200);
        }
        final b = jsonDecode(r.body), v = b['variables'];
        Map<String, dynamic> data;
        switch (b['operationName']) {
          case 'getTracks':
            metadataReads++;
            data = {
              'getTracks': [song],
            };
          case 'savedCatalog':
            data = {
              'collection': {'artists': [], 'releases': []},
            };
          case 'catalogDetail':
            final id = v['ids'][0] as String;
            opened.add(id);
            data = {
              'getArtists': [
                {
                  'id': id,
                  'title': id == '22' ? 'Guest' : 'Тестовый артист',
                  'popularTracks': [song],
                  'releases': [
                    {'id': '12', 'title': 'Другие песни', 'artists': []},
                  ],
                },
              ],
            };
          case 'getPlaylists':
            data = {'getPlaylists': []};
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
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: musicServiceConfig,
    );
    const legacy = Track(
      id: '7',
      title: 'Ночная дорога',
      artists: 'Тестовый артист',
      duration: 60,
    );
    final collab = Track.fromApi({
      'id': '8',
      'title': 'Совместная песня',
      'duration': 60,
      'artists': [
        {'id': '21', 'title': 'Tyler, The Creator'},
        {'id': '22', 'title': 'Guest'},
      ],
    });
    final app = AppController(store, music)
      ..account = const Account('fixture', 'Тест')
      ..api = api
      ..tracks = [legacy, collab];
    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      final collapse = find.byTooltip('Свернуть плеер').hitTestable();
      if (collapse.evaluate().isNotEmpty) {
        await tester.tap(collapse);
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
    }

    try {
      await music.initialize();
      await music.configure('fixture', api);
      await music.player.setVolume(0);
      await tester.pumpWidget(ZvukApp(app));
      await tester.pumpAndSettle();
      await tap(find.byType(ArtistLink).first);
      expect(opened.last, '11');
      expect(metadataReads, 1);
      expect(find.byType(CatalogDetailScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Другие песни'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(CatalogDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Другие песни'), findsOneWidget);
      expect(api.streams, 0); // Artist link wins over row's play gesture.
      await back();
      await music.playList([collab], 0);
      await until(() => music.player.playing && !music.loading);
      final streams = api.streams;
      openPlayer(tester.element(find.byType(MiniPlayer)), app);
      await tester.pumpAndSettle();
      await tap(
        find.descendant(
          of: find.byType(PlayerSheet),
          matching: find.byType(ArtistLink),
        ),
      );
      expect(find.text('Tyler, The Creator'), findsOneWidget);
      await tap(find.text('Guest'));
      expect(opened.last, '22');
      expect(api.streams, streams);
      expect(music.player.playing, true);
      await back();
      await music.pause();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('v190-01-player-artist-link');
      await back();
      await tap(find.text('Обзор'));
      await tap(find.text('Настроить поток'));
      await tap(find.text('Энергичное'));
      await tap(find.text('Рок'));
      await tap(find.text('На русском'));
      await tap(find.text('Хиты'));
      await tap(find.text('Применить'));
      expect(music.waveOptions.mood, WaveMood.energetic);
      expect(music.waveOptions.genres, ['rock']);
      expect(music.waveOptions.popularity, WavePopularity.hits);
      await tap(find.text('Настроить поток'));
      await tap(find.text('Грустное'));
      await back();
      expect(music.waveOptions.mood, WaveMood.energetic); // Cancel discards.
      await tap(find.text('Настроить поток'));
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tester.pumpAndSettle();
      await binding.takeScreenshot('v190-02-tuner-large');
      await tester.scrollUntilVisible(
        find.text('Инструментальная'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('v190-03-tuner-genres-large');
      expect(tester.takeException(), isNull);
      await tap(find.text('Сбросить'));
      await tap(find.text('Применить'));
      expect(music.waveOptions.isDefault, true);
      expect(
        await store.get('fixture', 'waveOptions'),
        const WaveOptions().toJson(),
      );
      expect(tester.takeException(), isNull);
      print(
        'ARTIST single/multiple/exact names/legacy hydration and uninterrupted playback passed; TUNER apply/cancel/reset and large text passed',
      );
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox());
      await music.disposeHandler();
      app.dispose();
      api.close();
      await server.close(force: true);
      await store.close();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
