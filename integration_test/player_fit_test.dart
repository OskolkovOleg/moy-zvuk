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
import 'package:zvuk_personal/ui/player_sheet.dart';
import 'package:zvuk_personal/ui/theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Player fits without scroll and votes stay quiet', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('zvuk-player-fit');
    final store = await LibraryStore.open(databasePath: '${dir.path}/test.db');
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: musicServiceConfig,
    );
    const a = Track(
      id: 'fit-a',
      title: 'Очень длинное название песни для небольшого экрана',
      artists: 'Артист с длинным названием',
      duration: 180,
    );
    const b = Track(
      id: 'fit-b',
      title: 'Следующая песня',
      artists: 'Артист',
      duration: 200,
    );
    final app = AppController(store, music)
      ..account = const Account('player-fit', 'Тест')
      ..tracks = [a, b]
      ..ranked = true;
    Future<void> checkFit() async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
      expect(find.text('Далее'), findsNothing);
      for (final finder in [
        find.byTooltip('Воспроизвести'),
        find.byTooltip('Следующий трек'),
        find.byKey(const Key('repeat-mode')),
        find.byKey(const Key('sleep-timer')),
      ]) {
        expect(finder.hitTestable(), findsOneWidget);
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      final top = tester.getTopLeft(find.byKey(const Key('player-seek'))).dy;
      expect(top, greaterThan(0));
    }

    try {
      await music.initialize();
      await music.configure('player-fit', null);
      music.playlist.replace([a, b], 0);
      music.sourceTitle = 'Любимое';
      music.revision.value++;
      await tester.pumpWidget(
        MaterialApp(theme: appTheme(), home: PlayerSheet(app)),
      );
      await checkFit();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      final wide =
          tester.view.physicalSize.width > tester.view.physicalSize.height;
      final mode = wide ? 'landscape' : 'portrait';
      await binding.takeScreenshot('v181-$mode-normal');
      await tester.tap(find.byTooltip('Плюс один: ${a.title}'));
      await tester.pumpAndSettle();
      expect(app.scoreFor(a), 11);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.byTooltip('Минус один: ${a.title}'));
      await tester.pumpAndSettle();
      expect(app.scoreFor(a), 10);
      expect(find.byType(SnackBar), findsNothing);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await checkFit();
      expect(
        find.byTooltip('Плюс один: ${a.title}').hitTestable(),
        findsOneWidget,
      );
      await binding.takeScreenshot('v181-$mode-large');
      music.error.value =
          'Не удалось воспроизвести трек. Повтори или выбери следующий.';
      await checkFit();
      await binding.takeScreenshot('v181-$mode-error');
      music.error.value = null;
      await app.setSort(false);
      await checkFit();
      await tester.tap(find.byTooltip('Ниже: ${a.title}'));
      await tester.pumpAndSettle();
      expect(app.visibleTracks.map((t) => t.id), ['fit-b', 'fit-a']);
      expect(find.byType(SnackBar), findsNothing);
      await binding.takeScreenshot('v181-$mode-manual');
      print(
        'PLAYER FIT $mode: no scroll/overflow, visible controls, quiet votes, large text, error and manual order passed',
      );
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox());
      await music.disposeHandler();
      app.dispose();
      await store.close();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
