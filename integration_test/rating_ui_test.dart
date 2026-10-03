// ignore_for_file: avoid_print
import 'dart:io';

import 'package:audio_service/audio_service.dart' hide Rating;
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
import 'package:zvuk_personal/ui/widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Initial ten, compact rows, no removal and live rating position',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('zvuk-rating-ui');
      final store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      await music.initialize();
      await music.configure('rating-ui', null);
      const a = Track(
        id: 'a',
        title: 'Северный ветер',
        artists: 'Тестовый артист',
      );
      const b = Track(
        id: 'b',
        title: 'Ночная дорога',
        artists: 'Другой артист',
      );
      const c = Track(
        id: 'c',
        title: 'Очень длинное название песни для узкого экрана',
        artists: 'Название группы',
      );
      final app = AppController(store, music)
        ..account = const Account('rating-ui', 'Тест');
      app.tracks = [c, a, b];
      await store.saveTracks('rating-ui', 'favorites', app.tracks);
      await app.vote(a, 1);
      await app.vote(a, 1);
      await app.vote(c, 1);
      await app.setSort(true);
      // UI fixture: the shuffled queue starts with the lowest-ranked song.
      music.playlist.replace([b, a], 0);
      music.isShuffled = true;
      music.sourceTitle = 'Любимое · топ 2';
      music.revision.value++;
      final queueBefore = music.playlist.tracks.map((t) => t.id).toList();
      try {
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        expect(app.scoreFor(b), 10);
        expect(find.text('Твой счёт'), findsNothing);
        expect(
          tester.getSize(find.byType(TrackTile).first).height,
          lessThanOrEqualTo(60),
        );
        final plus = find.byTooltip('Плюс один: ${a.title}');
        final artwork = find.descendant(
          of: find.byType(TrackTile).first,
          matching: find.byType(Artwork),
        );
        expect(
          (tester.getCenter(plus).dy - tester.getCenter(artwork).dy).abs(),
          lessThan(1),
        );
        expect(tester.getSize(plus).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(plus).height, greaterThanOrEqualTo(48));
        expect(find.text('№ 3 по баллам'), findsOneWidget);
        await binding.takeScreenshot('v130-01-compact-library');

        app.setUnrated(true);
        await tester.pumpAndSettle();
        expect(app.visibleTracks, [b]);
        await tester.tap(find.byTooltip('Минус один: ${b.title}'));
        await tester.pumpAndSettle();
        expect(app.unrated, false);
        expect(app.visibleTracks, hasLength(3));
        expect(app.scoreFor(b), 9);
        expect(find.byType(SnackBar), findsNothing);
        expect(music.error.value, isNull);
        ScaffoldMessenger.of(tester.element(find.byType(TrackTile).first))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byType(MiniPlayer),
                matching: find.byType(InkWell),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('№ 3 из 3 по баллам'), findsOneWidget);
        for (var i = 0; i < 4; i++) {
          await tester.tap(
            find.byTooltip('Плюс один: ${b.title}').hitTestable(),
          );
          await tester.pumpAndSettle();
        }
        expect(app.scoreFor(b), 13);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(find.text('Далее'), findsNothing);
        expect(find.text('№ 1 из 3 по баллам'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(PlayerSheet)))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v130-02-rating-position');
        for (var i = 0; i < 14; i++) {
          await app.vote(b, -1);
        }
        await tester.pumpAndSettle();
        expect(app.scoreFor(b), -1);
        expect(find.text('№ 3 из 3 по баллам'), findsOneWidget);
        expect(app.visibleTracks, hasLength(3));
        expect(
          (await store.loadTracks('rating-ui', 'favorites')),
          hasLength(3),
        );
        expect(music.playlist.tracks.map((t) => t.id), queueBefore);
        expect(music.playlist.index, 0);

        app.tracks = [a, c];
        await app.setSort(false);
        await tester.pumpAndSettle();
        expect(find.text('Нет в текущем списке'), findsOneWidget);
        app.tracks = [c, a, b];
        await app.setSort(true);
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('v130-03-player-large-text');
        await tester.tap(find.byTooltip('Свернуть плеер'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v130-04-library-large-text');
        expect(
          tester.getSize(find.byType(TrackTile).first).height,
          lessThanOrEqualTo(80),
        );
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpAndSettle();
        final title = find.descendant(
          of: find.byType(TrackTile),
          matching: find.text(b.title),
        );
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        await tester.longPress(title);
        await tester.pumpAndSettle();
        expect(find.text('Следующим'), findsOneWidget);
        expect(find.text('В конец очереди'), findsOneWidget);
        expect(tester.takeException(), isNull);
        print(
          'BASELINE 10, COMPACT rows, NEGATIVE retained, RANK updates, QUEUE independent, LONG_PRESS menu: passed',
        );
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
        await music.disposeHandler();
        app.dispose();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
