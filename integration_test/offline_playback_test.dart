// ignore_for_file: avoid_print
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' as clips;
import '../test/download_manager_test.dart' show waitDownloads;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Downloaded audio survives reopen and plays offline in background',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Офлайн-плеер'))),
      );
      final directory = await Directory.systemTemp.createTemp(
        'zvuk-offline-playback',
      );
      var store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.headers.contentType = ContentType('audio', 'wav');
        final bytes = clips.silence(request.uri.path == '/first.wav' ? 3 : 20);
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      final api = clips.ClipApi(server.port);
      final download = DownloadManager(store);
      const songs = [
        Track(id: 'first', title: 'Офлайн первый', duration: 3),
        Track(id: 'second', title: 'Офлайн второй', duration: 20),
      ];
      await download.configure('offline-test', api);
      await download.enqueue(songs);
      await waitDownloads(download);
      expect(download.tracks, hasLength(2));
      await download.close();
      await server.close(force: true);
      api.close();
      await store.close();
      store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      final app = AppController(store, music)
        ..account = const Account('offline-test', 'Офлайн')
        ..tracks = songs;
      const bridge = MethodChannel('zvuk.test');
      Future<Map<dynamic, dynamic>> notification() async =>
          (await bridge.invokeMapMethod<dynamic, dynamic>('notification'))!;
      try {
        await music.initialize();
        await music.configure(
          'offline-test',
          null,
        ); // no API or credential available
        expect(music.downloads.tracks, hasLength(2));
        await music.player.setVolume(0);
        await music.playList(music.downloads.tracks, 0, title: 'Скачанное');
        await clips.until(
          () => music.player.playing && music.position.inMilliseconds > 150,
        );
        await music.seek(const Duration(seconds: 1));
        await bridge.invokeMethod<void>('background');
        await clips.until(
          () =>
              music.playlist.index == 1 &&
              music.player.playing &&
              !music.loading,
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final info = await notification();
        expect(info['foreground'], true);
        expect(info['title'], 'Офлайн второй');
        expect(info['ratingScore'], 10);
        await bridge.invokeMethod<void>('mediaCommand', 'pause');
        await clips.until(() => !music.player.playing);
        await bridge.invokeMethod<void>('mediaCommand', 'play');
        await clips.until(() => music.player.playing);
        await bridge.invokeMethod<void>(
          info['sdk'] as int < 33
              ? 'notificationRatingAction'
              : 'customMediaAction',
          'Плюс 1 балл',
        );
        await clips.until(() => app.scoreFor(songs[1]) == 11);
        await music.seek(const Duration(seconds: 19));
        await clips.until(() => !music.player.playing && !music.loading);
        expect(music.playlist.index, 1);
        expect(music.error.value, isNull);
        expect(requests, 2);
        await music.playList(songs, 0);
        await clips.until(() => music.player.playing && !music.loading);
        await bridge.invokeMethod<void>('mediaCommand', 'next');
        await clips.until(
          () =>
              music.playlist.index == 1 &&
              music.player.playing &&
              !music.loading,
        );
        expect(requests, 2);
        print(
          'OFFLINE reopened persisted audio: API-null local files, seek, natural next, end-stop, background notification, ratings and media-next passed',
        );
      } finally {
        app.dispose();
        await music.disposeHandler();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
