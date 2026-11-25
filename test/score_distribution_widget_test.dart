import 'dart:io';

import 'package:audio_service/audio_service.dart' hide Rating;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/data/library_filter.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/playback_queue.dart';
import 'package:zvuk_personal/playback/sleep_timer.dart';
import 'package:zvuk_personal/ui/score_distribution_chart.dart';
import 'package:zvuk_personal/ui/score_distribution_screen.dart';
import 'package:zvuk_personal/ui/settings_screen.dart';
import 'package:zvuk_personal/ui/theme.dart';

import 'ui_capture.dart';

class _Store implements LibraryStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements AudioPlayer {
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Music extends BaseAudioHandler implements MusicHandler {
  _Music(LibraryStore store)
    : downloads = DownloadManager(store, directory: Directory.systemTemp);
  @override
  final DownloadManager downloads;
  @override
  final revision = ValueNotifier(0);
  @override
  final error = ValueNotifier<String?>(null);
  @override
  final playlist = PlaybackQueue();
  @override
  final player = _Player();
  @override
  final audioPreferences = const AudioPreferences();
  @override
  final sleepTimer = SleepTimerState();
  @override
  AudioServiceRepeatMode get repeatMode => AudioServiceRepeatMode.none;
  @override
  Duration get position => const Duration(seconds: 30);
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  bool get loading => false;
  @override
  bool get canSkipNext => playlist.hasNext;
  @override
  Future<void> Function(String, Track, int)? onNotificationVote;
  int commands = 0;
  @override
  Future<void> play() async {
    commands++;
  }

  @override
  Future<void> pause() async {
    commands++;
  }

  @override
  Future<void> skipToNext() async {
    commands++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadUiFonts);
  late AppController app;
  late _Music music;
  const a = Track(id: 'a', title: 'Ночная дорога', artists: 'Исполнитель'),
      b = Track(id: 'b', title: 'B'),
      c = Track(id: 'c', title: 'C');
  setUp(() {
    final store = _Store();
    music = _Music(store);
    app = AppController(store, music)
      ..account = const Account('owner', 'Fixture')
      ..favoriteTracks = [a, b, c, a]
      ..tracks = [const Track(id: 'playlist', title: 'Плейлист')]
      ..listId = 'playlist'
      ..ratings = {
        'a': const Rating(10, 0),
        'b': const Rating(10, 1, frozen: true),
        'c': const Rating(12, 3),
        'playlist': const Rating(1000, 0),
      };
    music.playlist.replace([a, b], 0);
    music.playbackState.add(PlaybackState(playing: true));
  });
  tearDown(() async {
    app.dispose();
    music.downloads.dispose();
    music.revision.dispose();
    music.error.dispose();
    await music.playbackState.close();
  });
  Future<void> show(WidgetTester tester, {bool settings = false}) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: settings
              ? Scaffold(body: SettingsScreen(app))
              : ScoreDistributionScreen(app),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Settings opens whole-library distribution and selection leaves playback and filters alone',
    (tester) async {
      app.setLibraryFilter(LibraryFilter(minScore: 100));
      await show(tester, settings: true);
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-distribution')),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('settings-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('settings-distribution')));
      await tester.pumpAndSettle();
      expect(find.byType(ScoreDistributionScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('distribution-total'))).data,
        '3 песни',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('score-band-12-12')),
      );
      await tester.tap(find.byKey(const ValueKey('score-band-12-12')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('distribution-share'))).data,
        '1 песня · 33,3% библиотеки',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('score-band-11-11')),
      );
      await tester.tap(find.byKey(const ValueKey('score-band-11-11')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('distribution-share'))).data,
        '0 песен · 0% библиотеки',
      );
      expect(app.libraryFilter.minScore, 100);
      expect(music.commands, 0);
      expect(music.playlist.current!.id, 'a');
      expect(music.playlist.tracks.map((t) => t.id), ['a', 'b']);
      expect(music.playbackState.value.playing, true);
      expect(tester.takeException(), null);
    },
  );
  for (final large in [false, true]) {
    testWidgets(
      'Distribution renders and offers accessible selection at ${large ? '320dp enlarged' : '360dp'}',
      (tester) async {
        tester.view.physicalSize = Size(large ? 640 : 720, 1440);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (large) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        const counts = [3, 8, 14, 29, 72, 120, 60, 35, 17, 9, 3, 1];
        app.favoriteTracks = [];
        app.ratings = {};
        for (var n = 0; n < counts.length; n++) {
          for (var i = 0; i < counts[n]; i++) {
            final id = '$n-$i';
            app.favoriteTracks.add(Track(id: id, title: 'Fixture'));
            app.ratings[id] = Rating(n + 5, 1);
          }
        }
        await show(tester);
        await captureUi(tester, 'distribution-${large ? '320-large' : '360'}');
        expect(
          tester.widget<Text>(find.byKey(const Key('distribution-total'))).data,
          '371 песня',
        );
        await tester.ensureVisible(
          find.byKey(const Key('distribution-choose-score')),
        );
        await tester.tap(find.byKey(const Key('distribution-choose-score')));
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'distribution-picker-${large ? '320-large' : '360'}',
        );
        await tester.tap(find.text('5 баллов').first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const Key('distribution-share'))).data,
          '3 песни · 0,8% библиотеки',
        );
        expect(music.commands, 0);
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets(
    'Live votes update the distribution and a changed account clears page and picker',
    (tester) async {
      await show(tester);
      app.ratings['a'] = const Rating(12, 2);
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('distribution-share'))).data,
        '2 песни · 66,7% библиотеки',
      );
      await tester.tap(find.byKey(const Key('distribution-choose-score')));
      await tester.pumpAndSettle();
      app.account = const Account('other', 'Other');
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Выбрать балл'), findsNothing);
      expect(find.text('12 баллов'), findsNothing);
      expect(find.text('Аккаунт изменился'), findsWidgets);
      expect(music.commands, 0);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'Empty and single-score libraries do not invent data or divide by zero',
    (tester) async {
      app.favoriteTracks = [];
      await show(tester);
      expect(find.text('Пока нет песен'), findsOneWidget);
      expect(find.byType(ScoreDistributionChart), findsNothing);
      await captureUi(tester, 'distribution-empty');
      app.favoriteTracks = [a];
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('distribution-share'))).data,
        '1 песня · 100% библиотеки',
      );
      expect(tester.takeException(), null);
    },
  );
}
