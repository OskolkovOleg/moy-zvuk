// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' as clips;
import 'favorite_ui_test.dart' show FavoriteFixtureApi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native favorite action changes artwork card quietly in background',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Проверка избранного'))),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.add(clips.silence(120));
        await request.response.close();
      });
      final dir = await Directory.systemTemp.createTemp(
        'zvuk-notification-favorite',
      );
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final cover = await rootBundle.load('assets/brand/icon.png');
      final coverFile = File('${dir.path}/cover.png');
      await coverFile.writeAsBytes(
        cover.buffer.asUint8List(cover.offsetInBytes, cover.lengthInBytes),
      );
      final a = Track(
        id: 'notification-favorite-a',
        title: 'Ночная дорога',
        artists: 'Тестовый артист',
        duration: 120,
        imageUrl: coverFile.uri.toString(),
      );
      const b = Track(
        id: 'notification-favorite-b',
        title: 'Тёплый вечер',
        artists: 'Другой артист',
        duration: 120,
      );
      final api = FavoriteFixtureApi(server.port, [a, b], {});
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      final app = AppController(store, music)
        ..account = const Account('notification-favorite', 'Тест')
        ..api = api
        ..tracks = [a, b]
        ..listId = 'fixture-playlist';
      const bridge = MethodChannel('zvuk.test');
      Future<Map<dynamic, dynamic>> info() async =>
          (await bridge.invokeMapMethod<dynamic, dynamic>('notification'))!;
      try {
        await music.initialize();
        await music.configure(app.account!.id, api);
        await music.player.setVolume(0);
        await music.playList([a, b], 0);
        await clips.until(() => music.position.inMilliseconds > 100);
        final source = music.player.sequence.first;
        await bridge.invokeMethod<void>('background');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final before = await info(), sdk = before['sdk'] as int;
        expect(before['style'], contains('MediaStyle'));
        expect(before['hasCustomView'], false);
        expect(before['hasArtwork'], true);
        expect(before['customLabels'], [
          'В любимое',
          'Минус 1 балл',
          'Плюс 1 балл',
        ]);
        if (sdk < 33) {
          expect(before['actions'], [
            'Pause',
            'Next',
            'В любимое',
            'Минус 1 балл',
            'Плюс 1 балл',
          ]);
        }
        Future<void> press(String label) => bridge.invokeMethod<void>(
          sdk < 33 ? 'notificationAction' : 'customMediaAction',
          label,
        );
        String action() => music.playbackState.value.controls
            .firstWhere(
              (c) => c.customAction?.name.startsWith('zvuk.favorite.') == true,
            )
            .customAction!
            .name;
        final stale = action();
        api.state.hold = Completer<void>();
        await press('В любимое');
        await clips.until(() => api.state.writes == 1);
        expect(await music.customAction(stale), false);
        api.state.hold!.complete();
        api.state.hold = null;
        await clips.until(() => app.isFavorite(a.id) && !app.serverBusy);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final liked = await info();
        expect(liked['customLabels'], [
          'Убрать из любимого',
          'Минус 1 балл',
          'Плюс 1 балл',
        ]);
        expect(
          (liked['customIcons'] as List).first,
          isNot((before['customIcons'] as List).first),
        );
        expect(liked['hasArtwork'], true);
        expect(liked['ratingScore'], 10);
        expect(music.player.playing, true);
        expect(music.player.sequence.first, same(source));
        expect(music.playlist.tracks.map((t) => t.id), [a.id, b.id]);
        expect(await music.customAction(stale), false);
        await bridge.invokeMethod<void>(
          sdk < 33 ? 'notificationTransport' : 'mediaCommand',
          'pause',
        );
        await clips.until(() => !music.player.playing);
        final pausedAt = music.position;
        await Future<void>.delayed(const Duration(milliseconds: 400));
        api.state.failRead = true;
        await press('Убрать из любимого');
        await clips.until(() => !app.isFavorite(a.id) && !app.serverBusy);
        expect(
          await store.loadTracks('notification-favorite', 'favorites'),
          isEmpty,
        );
        expect(music.position, pausedAt);
        expect(music.player.playing, false);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        api.state.failRead = false;
        api.state.failWrite = true;
        await press('В любимое');
        await clips.until(() => music.error.value != null);
        expect(app.isFavorite(a.id), false);
        api.state.failWrite = false;
        await press('В любимое');
        await clips.until(() => app.isFavorite(a.id) && !app.serverBusy);
        expect(music.error.value, isNull);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await press('Плюс 1 балл');
        await clips.until(() => app.scoreFor(a) == 11);
        await press('Минус 1 балл');
        await clips.until(() => app.scoreFor(a) == 10);
        expect(app.isFavorite(a.id), true);
        final old = action();
        print('NOTIFICATION_FAVORITE_CAPTURE_READY SDK=$sdk');
        await Future<void>.delayed(const Duration(seconds: 10));
        await music.skipToNext();
        await music.pause();
        expect(await music.customAction(old), false);
        expect(await music.customAction('zvuk.favorite.add:unknown'), false);
        expect(app.isFavorite(b.id), false);
        app.account = const Account('other-favorite', 'Другой');
        app.favoriteTracks = [];
        await music.configure('other-favorite', api);
        await music.playList([a], 0);
        await music.pause();
        expect(await music.customAction(old), false);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await press('В любимое');
        await clips.until(() => app.isFavorite(a.id) && !app.serverBusy);
        expect(
          (await store.loadTracks(
            'notification-favorite',
            'favorites',
          )).single.id,
          a.id,
        );
        expect(
          (await store.loadTracks('other-favorite', 'favorites')).single.id,
          a.id,
        );
        expect(find.byType(SnackBar), findsNothing);
        print(
          'NOTIFICATION FAVORITE API $sdk: native buttons, background/play/pause, artwork, persistence, duplicate/stale actions, API failures, rating controls and account isolation passed',
        );
      } finally {
        app.dispose();
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
