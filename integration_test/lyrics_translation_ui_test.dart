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
import 'package:zvuk_personal/data/lyrics_translation.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/lyrics_screen.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';

import '../test/lyrics_translation_test.dart' as translation_tests;
import 'background_controls_test.dart' show silence, until;
import 'personal_ui_test.dart' show PersonalFixtureApi;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Lyrics translation state', translation_tests.main);
  testWidgets(
    'Native English→Russian pairs, seeking, narrow layout and offline model',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp(
        'zvuk-lyrics-translation',
      );
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
      const track = Track(
        id: 'translation-fixture',
        title: 'The open road',
        artists: 'Тест перевода',
        duration: 60,
      );
      var offlineApi = false;
      final api = PersonalFixtureApi(
        server.port,
        MockClient(
          (request) async => offlineApi
              ? http.Response('{}', 503)
              : http.Response(
                  jsonEncode({
                    'result': {
                      'lyrics': '[00:00]The sun is shining in the sky.\n[00:10]I am walking home with my friends.\n[00:20]We can hear the birds singing.\n[00:30]The sun is shining in the sky.',
                    },
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                ),
        ),
      );
      final app = AppController(store, music)
        ..account = const Account('translation-fixture', 'Тест')
        ..api = api
        ..tracks = [track];
      try {
        await music.initialize();
        await music.configure('translation-fixture', api);
        await music.player.setVolume(0);
        await music.playList([track], 0);
        await until(() => music.player.position.inMilliseconds > 100);
        await music.pause();
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        openLyrics(tester.element(find.byType(MiniPlayer).first), app, track);
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (find
                .byKey(const ValueKey('lyrics-translation:0'))
                .evaluate()
                .isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(seconds: 1));
          expect(find.textContaining('Перевод недоступен'), findsNothing);
        }
        final first = find.byKey(const ValueKey('lyrics-translation:0'));
        expect(first, findsOneWidget);
        expect(tester.widget<Text>(first).data, matches(RegExp('[А-Яа-яЁё]')));
        final original = tester.widget<Text>(
          find.text('The sun is shining in the sky.').first,
        );
        final translated = tester.widget<Text>(first);
        expect(translated.style!.fontSize, lessThan(original.style!.fontSize!));
        expect(translated.style!.color, isNot(original.style!.color));
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v112-05-lyrics-pairs');
        final second = find.byKey(const ValueKey('lyrics-translation:1'));
        await tester.ensureVisible(second);
        await tester.tap(second);
        await tester.pumpAndSettle();
        expect(music.position.inSeconds, 10);
        await tester.ensureVisible(find.widgetWithText(FilterChip, 'Перевод'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'Перевод'));
        await tester.pumpAndSettle();
        expect(first, findsNothing);
        await tester.tap(find.widgetWithText(FilterChip, 'Перевод'));
        await tester.pumpAndSettle();
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        await tester.ensureVisible(second);
        await tester.pumpAndSettle();
        expect(
          tester.getBottomRight(second).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(MiniPlayer)).dy),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        await binding.takeScreenshot('v112-06-lyrics-pairs-large');
        expect(tester.takeException(), isNull);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pageBack();
        await tester.pumpAndSettle();
        offlineApi = true;
        openLyrics(tester.element(find.byType(MiniPlayer).first), app, track);
        await tester.pumpAndSettle();
        expect(first, findsOneWidget);
        expect(
          (await store.get(
            'translation-fixture',
            'lyrics-en-ru-v1:${track.id}',
          ))['translated'],
          hasLength(4),
        );
        final engine = DeviceLyricsTranslationEngine();
        try {
          var downloaded = false;
          await engine.prepare(() => downloaded = true);
          expect(downloaded, false);
          print('LYRICS_OFFLINE_CHECK_READY');
          await Future<void>.delayed(const Duration(seconds: 10));
          final offline = await engine.translate(
            'My family lives near a beautiful river.',
          );
          expect(offline, matches(RegExp('[А-Яа-яЁё]')));
          print('LYRICS_OFFLINE_CHECK_PASSED');
        } finally {
          await engine.close();
        }
        print(
          'LYRICS: native language detection, Wi-Fi model, paired secondary text, seek, cache, offline translation passed',
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
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
