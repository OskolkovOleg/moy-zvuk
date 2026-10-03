// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/downloads/download_record.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/downloads_screen.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/widgets.dart';

import 'background_controls_test.dart' show ClipApi, silence, until;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Download controls and offline library fit narrow and large-text screens',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'zvuk-downloads-ui',
      );
      final store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Completer<void>? gate;
      var fail = false;
      server.listen((request) async {
        if (fail) {
          request.response.statusCode = 503;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType('audio', 'wav');
        final bytes = silence(60);
        request.response.contentLength = bytes.length;
        request.response.add(bytes.sublist(0, 12000));
        await request.response.flush();
        await gate?.future;
        try {
          request.response.add(bytes.sublist(12000));
          await request.response.close();
        } catch (_) {
          /* The test may cancel a transfer. */
        }
      });
      final api = ClipApi(server.port);
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      const songs = [
        Track(
          id: 'night',
          title: 'Ночная дорога',
          artists: 'Тестовый артист',
          duration: 60,
        ),
        Track(
          id: 'evening',
          title: 'Тёплый вечер с очень длинным названием',
          artists: 'Другой артист',
          duration: 60,
        ),
      ];
      final app = AppController(store, music)
        ..account = const Account('download-ui', 'Тест')
        ..api = api
        ..tracks = songs;
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 500));
      }

      Future<void> screenshot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
      }

      try {
        await music.initialize();
        await music.configure(app.account!.id, api);
        await music.player.setVolume(0);
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await tap(find.text('Скачанное'));
        expect(find.text('Музыка с собой'), findsOneWidget);
        await screenshot('v110-01-downloads-empty');
        await tester.pageBack();
        await tester.pumpAndSettle();
        gate = Completer<void>();
        await tester.longPress(find.text(songs.first.title));
        await tester.pumpAndSettle();
        await tap(find.text('Скачать для прослушивания без интернета'));
        await until(
          () =>
              music.downloads.forTrack(songs.first.id)?.state ==
                  DownloadState.downloading &&
              music.downloads.forTrack(songs.first.id)!.bytes > 0,
        );
        await tap(find.text('Скачанное'));
        await screenshot('v110-02-downloading');
        await tap(find.byTooltip('Отменить: ${songs.first.title}'));
        await until(() => music.downloads.items.isEmpty);
        gate.complete();
        gate = null;
        fail = true;
        await music.downloads.enqueue([songs.first]);
        await until(
          () =>
              music.downloads.forTrack(songs.first.id)?.state ==
              DownloadState.failed,
        );
        await screenshot('v110-03-download-failed');
        fail = false;
        await tap(find.byTooltip('Повторить: ${songs.first.title}'));
        await until(
          () =>
              music.downloads.forTrack(songs.first.id)?.state ==
              DownloadState.ready,
        );
        await music.downloads.enqueue([songs.last]);
        await until(() => music.downloads.pendingCount == 0);
        await app.vote(songs.last, 1);
        await screenshot('v110-04-downloads-ready');
        expect(
          find.byType(TrackTile),
          findsNWidgets(2),
        ); // library retained under route + downloaded rows
        await tap(find.byKey(const Key('play-downloads')));
        await until(() => music.player.playing && !music.loading);
        expect(
          music.playlist.current!.id,
          songs.last.id,
        ); // highest score first
        await music.pause();
        await tap(find.text('Перемешать'));
        await tap(find.text('Лучшие по баллам'));
        await tap(find.byKey(const Key('start-shuffle')));
        await until(() => music.player.playing && !music.loading);
        expect(music.playlist.tracks, hasLength(2));
        await music.pause();
        // Inspect the same screen under accessibility text scaling.
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: DownloadsScreen(app),
          ),
        );
        await tester.pumpAndSettle();
        await screenshot('v110-05-downloads-large-text');
        await tap(find.byTooltip('Управление загрузками'));
        await tap(find.text('Удалить все загрузки'));
        await tap(find.text('Удалить'));
        await until(() => music.downloads.items.isEmpty);
        expect(app.scoreFor(songs.last), 11);
        expect(app.tracks, hasLength(2));
        expect(tester.takeException(), isNull);
        print(
          'DOWNLOADS UI: empty, progress, cancel, failure/retry, ready, score order, best-N shuffle, large text and safe deletion passed',
        );
      } finally {
        if (gate != null && !gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
