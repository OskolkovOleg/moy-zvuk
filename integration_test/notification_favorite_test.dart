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

import 'favorite_ui_test.dart' show FavoriteFixtureApi;
import 'background_controls_test.dart' as clips;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native notification plus collects and synchronizes once; minus keeps song',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      const track = Track(
        id: 'notification-new',
        title: 'Новая песня',
        duration: 60,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.add(clips.silence(60));
        await r.response.close();
      });
      final dir = await Directory.systemTemp.createTemp('score-notification');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final api = FavoriteFixtureApi(server.port, [track], {});
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      final app = AppController(store, music)
        ..account = const Account('score-notification', 'Тест')
        ..api = api;
      const bridge = MethodChannel('zvuk.test');
      try {
        await music.initialize();
        await music.configure('score-notification', api);
        await music.player.setVolume(0);
        await music.playList([track], 0);
        await clips.until(() => music.position.inMilliseconds > 150);
        await bridge.invokeMethod<void>('background');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final info = (await bridge.invokeMapMethod<dynamic, dynamic>(
          'notification',
        ))!;
        expect(info['ratingScore'], 9);
        expect(info['customLabels'], ['Минус 1 балл', 'Плюс 1 балл']);
        final action = (info['sdk'] as int) < 33
            ? 'notificationAction'
            : 'customMediaAction';
        await bridge.invokeMethod<void>(action, 'Плюс 1 балл');
        await clips.until(() => app.scoreFor(track) == 10);
        await app.syncLibraryAdds();
        expect(app.isFavorite(track.id), true);
        expect(api.state.likes, contains(track.id));
        expect(api.state.writes, 1);
        expect(music.player.playing, true);
        expect(music.playlist.index, 0);
        await bridge.invokeMethod<void>(action, 'Минус 1 балл');
        await clips.until(() => app.scoreFor(track) == 9);
        expect(app.isFavorite(track.id), true);
        expect(api.state.writes, 1);
        final updated = (await bridge.invokeMapMethod<dynamic, dynamic>(
          'notification',
        ))!;
        expect(updated['ratingScore'], 9);
        expect(updated['style'], contains('MediaStyle'));
        expect(updated['hasCustomView'], false);
        expect(
          await music.customAction(
            'zvuk.favorite.add:0:score-notification:${track.id}',
          ),
          false,
        );
        print(
          'NATIVE PLUS: 9 -> 10, local library and remote collection updated once; minus retains song and MediaStyle',
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
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
