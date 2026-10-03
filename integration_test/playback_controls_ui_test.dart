// ignore_for_file: avoid_print
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';
import 'package:zvuk_personal/ui/queue_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Editable queue, timer and repeat in the compact player at narrow widths',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('zvuk-controls-ui');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      const tracks = [
        Track(
          id: 'a',
          title: 'Ночная дорога',
          artists: 'Тестовый артист',
          duration: 180,
        ),
        Track(
          id: 'b',
          title: 'Тёплый вечер',
          artists: 'Другой артист',
          duration: 190,
        ),
        Track(
          id: 'c',
          title: 'Новые огни',
          artists: 'Тестовый артист',
          duration: 200,
        ),
        Track(
          id: 'a',
          title: 'Ночная дорога',
          artists: 'Тестовый артист',
          duration: 180,
        ),
      ];
      await store.put('fixture', 'queue', {
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'index': 0,
        'title': 'Вечерний плейлист',
        'position': 35000,
      });
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      final app = AppController(store, music)
        ..account = const Account('fixture', 'Тест')
        ..tracks = tracks
        ..ranked = true;
      Future<void> visibleTap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      try {
        await music.initialize();
        await music.configure('fixture', null);
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        openPlayer(tester.element(find.byType(MiniPlayer)), app);
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await visibleTap(find.byKey(const Key('repeat-mode')));
        expect(music.repeatMode, AudioServiceRepeatMode.all);
        await visibleTap(find.byKey(const Key('repeat-mode')));
        expect(music.repeatMode, AudioServiceRepeatMode.one);
        await visibleTap(find.byKey(const Key('sleep-timer')));
        await tester.tap(find.text('Через 15 мин'));
        await tester.pumpAndSettle();
        expect(music.sleepTimer.deadline, isNotNull);
        await binding.takeScreenshot('v160-01-player');
        await visibleTap(find.byKey(const Key('sleep-timer')));
        await tester.tap(find.text('После песни'));
        await tester.pumpAndSettle();
        expect(music.sleepTimer.stopsAfterSong, true);
        await visibleTap(find.byKey(const Key('sleep-timer')));
        await tester.tap(find.text('Выключить таймер'));
        await tester.pumpAndSettle();
        expect(music.sleepTimer.active, false);
        await tester.tap(find.byTooltip('Очередь'));
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsOneWidget);
        final key = music.playlist.entryKey(0),
            oldVersion = music.playlist.version;
        await tester.drag(
          find.byKey(ValueKey('drag:$key')),
          const Offset(0, 165),
        );
        await tester.pumpAndSettle();
        expect(music.playlist.version, greaterThan(oldVersion));
        expect(music.playlist.index, greaterThan(0));
        expect(music.playlist.entryKey(music.playlist.index), key);
        expect(music.position.inSeconds, 35);
        await binding.takeScreenshot('v160-02-queue');
        await tester.tap(find.byTooltip('В очереди: Тёплый вечер'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Следующей'));
        await tester.pumpAndSettle();
        expect(music.playlist.tracks[music.playlist.index + 1].id, 'b');
        await tester.tap(find.byTooltip('В очереди: Новые огни'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Убрать из очереди'));
        await tester.pumpAndSettle();
        expect(music.playlist.tracks.any((t) => t.id == 'c'), false);
        expect(app.tracks, tracks);
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v160-03-queue-large');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Убрать оставшиеся'));
        await tester.pumpAndSettle();
        expect(music.playlist.hasNext, false);
        expect(music.repeatMode, AudioServiceRepeatMode.none);
        // Let the queue-clear confirmation expire before testing player buttons.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        music.isWave = true;
        music.revision.value++;
        await tester.tap(find.byTooltip('Плеер'));
        await tester.pumpAndSettle();
        expect(find.text('Поток подберёт следующую'), findsNothing);
        expect(find.text('Далее'), findsNothing);
        expect(find.byType(SingleChildScrollView), findsNothing);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('v160-04-wave-end-large');
        await visibleTap(find.byKey(const Key('repeat-mode')));
        expect(music.repeatMode, AudioServiceRepeatMode.one);
        await visibleTap(find.byKey(const Key('repeat-mode')));
        expect(music.repeatMode, AudioServiceRepeatMode.none);
        await visibleTap(find.byKey(const Key('sleep-timer')));
        await binding.takeScreenshot('v160-05-timer-large');
        expect(tester.takeException(), isNull);
        Navigator.pop(tester.element(find.text('Через 15 мин')));
        await tester.pumpAndSettle();
        print(
          'CONTROLS UI: drag, occurrence-safe actions, repeat, sleep picker, wave final preview, 1.6x text: passed',
        );
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        await music.disposeHandler();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
