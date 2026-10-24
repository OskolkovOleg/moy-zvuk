// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart' hide Rating;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';
import 'package:zvuk_personal/ui/queue_view.dart';
import 'package:zvuk_personal/ui/settings_screen.dart';

import '../test/widget_test.dart' as widgets;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Widgets on Android', widgets.main);
  testWidgets('Score ordering, top-down playback and range shuffle', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('zvuk-ui-test');
    final store = await LibraryStore.open(
      databasePath: '${directory.path}/test.db',
    );
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.oleg.zvuk_personal.test',
        androidNotificationChannelName: 'Проверка плеера',
        androidNotificationIcon: 'drawable/ic_stat_music',
      ),
    );
    await music.initialize();
    await music.player.setVolume(0);
    final app = AppController(store, music);
    await tester.pumpWidget(ZvukApp(app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подключить Звук'));
    await tester.pumpAndSettle();
    expect(find.text('Вставь токен своего аккаунта'), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('v120-01-connect');
    final credentials = jsonDecode(
      (await http.get(Uri.parse('http://127.0.0.1:18746/credential'))).body,
    );
    final api = ZvukApi(credentials['token']);
    try {
      app.account = const Account('ui-test', 'Олег');
      app.api = api;
      final favorites = await api.favorites();
      final playable = await api.tracks(['177981965', '180082552']);
      final known = playable.map((t) => t.id).toSet();
      // Test-only snapshot: put known full streams first for the player checks.
      // This does not write the personal account's favorites or playlists.
      app.tracks = [
        ...playable,
        ...favorites.where((t) => !known.contains(t.id)),
      ];
      app.playlists = await api.playlists();
      await store.saveTracks('ui-test', 'favorites', app.tracks);
      await music.configure('ui-test', api);
      await app.vote(app.tracks.first, 1);
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(app.visibleTracks.first.id, playable[0].id);
      expect((await store.ratings('ui-test'))[playable[0].id]!.score, 10);
      await binding.takeScreenshot('v140-02-library-by-score');
      final launchOrder = app.visibleTracks.map((t) => t.id).toList();
      await tester.tap(find.byKey(const Key('play-from-top')));
      await tester.pump();
      await music.player.positionStream
          .firstWhere((p) => p.inMilliseconds > 800)
          .timeout(const Duration(seconds: 45));
      expect(music.playlist.tracks.map((t) => t.id), launchOrder);
      expect(music.playlist.current!.id, playable[0].id);
      expect(music.sourceTitle, 'Мои песни');
      expect(music.playlist.tracks.map((t) => t.id), launchOrder);
      await music.seek(music.duration - const Duration(seconds: 1));
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while ((music.playlist.index != 1 || music.loading) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(music.playlist.index, 1);
      expect(music.playlist.current!.id, playable[1].id);
      expect(music.error.value, isNull);
      await music.pause();
      print(
        'SCORE_ORDER ratingsPreserved=passed TOP_DOWN queue=passed autoNext=passed',
      );
      await tester.pumpAndSettle();
      final mini = find.byType(MiniPlayer);
      await tester.tap(
        find.descendant(of: mini, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerSheet), findsOneWidget);
      expect(music.player.playing, false);
      expect(find.byTooltip('Воспроизвести').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Воспроизвести').hitTestable());
      await music.player.playingStream
          .firstWhere((playing) => playing)
          .timeout(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Пауза').hitTestable());
      await tester.pumpAndSettle();
      expect(music.player.playing, false);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('v120-04-player');
      await tester.tap(find.byTooltip('Очередь'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueView), findsOneWidget);
      await binding.takeScreenshot('v120-05-queue');
      await tester.tap(find.byTooltip('Плеер'));
      await tester.pumpAndSettle();
      // Real layout at a narrow viewport; controls must remain usable.
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PlayerSheet)).width, 360);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('player-seek')), findsOneWidget);
      await binding.takeScreenshot('v120-06-player-small');
      Navigator.of(tester.element(find.byType(PlayerSheet))).pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки').last);
      await tester.pumpAndSettle();
      expect(find.text('Сохранить в файл'), findsOneWidget);
      await binding.takeScreenshot('v120-07-settings');
      expect(tester.takeException(), isNull);
      // Isolate shuffle candidates from the live catalogue in a test-only list.
      app.tracks = playable;
      app.ratings = {
        playable[0].id: const Rating(18, 8),
        playable[1].id: const Rating(13, 3),
      };
      await tester.tap(find.text('Библиотека').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-filter')));
      await tester.pumpAndSettle();
      final slider = tester.widget<RangeSlider>(
        find.byKey(const Key('shuffle-score-slider')),
      );
      slider.onChanged!(const RangeValues(18, 18));
      await tester.pumpAndSettle();
      expect(find.text('Подходит 1 трек'), findsOneWidget);
      await binding.takeScreenshot('v120-08-shuffle-best');
      await tester.tap(find.byKey(const Key('apply-library-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shuffle-list')));
      await tester.pump();
      await music.player.positionStream
          .firstWhere((p) => p.inMilliseconds > 400)
          .timeout(const Duration(seconds: 45));
      expect(music.playlist.tracks, hasLength(1));
      expect(music.playlist.current!.id, playable[0].id);
      expect(music.isShuffled, true);
      expect(music.sourceTitle, 'Мои песни · 18–18 баллов');
      await music.pause();
      await music.configure('other-test-account', null);
      await music.configure('ui-test', api);
      expect(music.isShuffled, true);
      expect(music.playlist.tracks, hasLength(1));
      expect(music.player.playing, false);
      await app.playShuffled();
      expect(
        music.playlist.tracks.map((t) => t.id),
        unorderedEquals(playable.map((t) => t.id)),
      );
      await music.pause();
      expect(tester.takeException(), isNull);
      print('SHUFFLE scoreRange=passed all=passed restoreMode=passed');
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
      await music.disposeHandler();
      await store.close();
      api.close();
      app.dispose();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
