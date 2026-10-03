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
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' as clips;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Notification ratings persist quietly without changing playback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Оценки из уведомления'))),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.add(clips.silence(60));
      await request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp(
      'zvuk-notification-rating',
    );
    final store = await LibraryStore.open(databasePath: '${dir.path}/test.db');
    final api = clips.ClipApi(server.port);
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: musicServiceConfig,
    );
    const a = Track(
      id: 'rating-a',
      title: 'Ночная дорога',
      artists: 'Тестовый артист',
      duration: 60,
    );
    const b = Track(
      id: 'rating-b',
      title: 'Тёплый вечер',
      artists: 'Другой артист',
      duration: 60,
    );
    final app = AppController(store, music)
      ..account = const Account('notification-rating', 'Тест')
      ..tracks = [a, b]
      ..ranked = true;
    const bridge = MethodChannel('zvuk.test');
    Future<Map<dynamic, dynamic>> notification() async =>
        (await bridge.invokeMapMethod<dynamic, dynamic>('notification'))!;
    try {
      await music.initialize();
      await music.configure(app.account!.id, api);
      await music.player.setVolume(0);
      await music.playList([a, b], 0);
      await clips.until(() => music.position.inMilliseconds > 150);
      await bridge.invokeMethod<void>('background');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final info = await notification();
      expect(info['present'], true);
      expect(info['foreground'], true);
      expect(info['customLabels'], ['Минус 1 балл', 'Плюс 1 балл']);
      expect(
        (info['customIcons'] as List).every((id) => (id as int) > 0),
        true,
      );
      final sdk = info['sdk'] as int;
      if (sdk < 33) expect(info['hasRatingView'], true);
      expect((info['actions'] as List).contains('Stop'), false);
      expect(info['ratingScore'], 10);
      if (sdk < 33) expect(info['hasRatingView'], true);
      Future<void> press(String label) => bridge.invokeMethod<void>(
        sdk < 33 ? 'notificationRatingAction' : 'customMediaAction',
        label,
      );

      // Real notification PendingIntent on older Android, MediaSession on 13+.
      await press('Плюс 1 балл');
      await clips.until(() => app.scoreFor(a) == 11);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((await notification())['ratingScore'], 11);
      expect(music.player.playing, true);
      await bridge.invokeMethod<void>(
        sdk < 33 ? 'notificationTransport' : 'mediaCommand',
        'pause',
      );
      await clips.until(() => !music.player.playing);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final pausedAt = music.position;
      for (var i = 0; i < 3; i++) {
        await press('Плюс 1 балл');
      }
      for (var i = 0; i < 2; i++) {
        await press('Минус 1 балл');
      }
      await clips.until(() => app.scoreFor(a) == 12);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((await notification())['ratingScore'], 12);
      expect(music.player.playing, false);
      expect(music.position, pausedAt);
      expect(music.playlist.index, 0);
      expect(music.playlist.tracks.map((t) => t.id), [a.id, b.id]);
      expect(app.scoreFor(b), 10);
      expect((await store.ratings(app.account!.id))[a.id]!.score, 12);
      expect(find.byType(SnackBar), findsNothing);
      await app.vote(a, -1);
      await press('Плюс 1 балл');
      await clips.until(() => app.scoreFor(a) == 12);
      print('NOTIFICATION_RATING_CAPTURE_READY SDK=$sdk');
      await Future<void>.delayed(const Duration(seconds: 20));

      final stale = music.playbackState.value.controls.last.customAction!.name;
      await music.skipToNext();
      await music.pause();
      expect(await music.customAction(stale), false);
      expect(await music.customAction('unknown'), false);
      expect(app.scoreFor(a), 12);
      expect(app.scoreFor(b), 10);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await press('Минус 1 балл');
      await clips.until(() => app.scoreFor(b) == 9);

      app.account = const Account('other-account', 'Другой');
      app.ratings = {};
      await music.configure('other-account', api);
      expect(await music.customAction(stale), false);
      expect(
        music.playbackState.value.controls.any((c) => c.customAction != null),
        false,
      );
      await music.playList([a], 0);
      await music.pause();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await press('Плюс 1 балл');
      await clips.until(() => app.scoreFor(a) == 11);
      expect((await store.ratings('notification-rating'))[a.id]!.score, 12);
      expect((await store.ratings('notification-rating'))[b.id]!.score, 9);
      expect(music.error.value, isNull);
      print(
        'NOTIFICATION RATINGS API $sdk: native actions, background, pause, accumulation, persistence, stale action and account isolation passed',
      );
    } finally {
      app.dispose();
      await music.disposeHandler();
      api.close();
      await server.close(force: true);
      await store.close();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
