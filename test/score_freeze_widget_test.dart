import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart' hide Rating;
import 'package:just_audio/just_audio.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_filter.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/playback_queue.dart';
import 'package:zvuk_personal/playback/sleep_timer.dart';
import 'package:zvuk_personal/ui/library_screen.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';
import 'package:zvuk_personal/ui/score_badge.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/widgets.dart';

import 'ui_capture.dart';

class _Store implements LibraryStore {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Player implements AudioPlayer {
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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
  Duration get duration => const Duration(minutes: 3);
  @override
  Duration get position => const Duration(seconds: 30);
  @override
  bool get loading => false;
  @override
  bool get isShuffled => false;
  @override
  bool get isWave => false;
  @override
  bool get canSkipNext => playlist.hasNext;
  @override
  String get sourceTitle => 'Мои песни';
  @override
  AudioServiceRepeatMode get repeatMode => AudioServiceRepeatMode.none;
  @override
  final sleepTimer = SleepTimerState();
  @override
  Future<void> Function(String, Track, int)? onNotificationVote;
  List<Track> played = [];
  @override
  Future<void> playList(
    List<Track> tracks,
    int index, {
    String title = 'Queue',
    bool shuffled = false,
  }) async => played = List.of(tracks);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _App extends AppController {
  _App(super.store, super.music);
  @override
  Future<void> toggleScoreFreeze(Track track) async {
    final r = ratings[track.id] ?? const Rating(9, 0);
    ratings = {
      ...ratings,
      track.id: Rating(r.score, r.count, frozen: !r.frozen),
    };
    notifyListeners();
  }
}

void main() {
  setUpAll(loadUiFonts);
  late _App app;
  late _Music music;
  const a = Track(
    id: 'a',
    title: 'На своём уровне',
    artists: 'Исполнитель',
    genres: [TrackGenre(id: 'rock', name: 'Rock')],
    explicit: false,
  );
  const b = Track(
    id: 'b',
    title: 'Ещё переслушать',
    artists: 'Другой исполнитель',
    genres: [TrackGenre(id: 'rock', name: 'Rock')],
    explicit: false,
  );
  setUp(() {
    final store = _Store();
    music = _Music(store);
    app = _App(store, music)
      ..account = const Account('owner', 'Fixture')
      ..tracks = [a, b]
      ..favoriteTracks = [a, b]
      ..ratings = {'a': const Rating(10, 1), 'b': const Rating(12, 3)};
  });
  tearDown(() async {
    app.dispose();
    music.downloads.dispose();
    music.error.dispose();
    music.revision.dispose();
    await music.playbackState.close();
  });
  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: app,
            builder: (_, _) => LibraryScreen(app),
          ),
        ),
      ),
    ),
  );

  for (final large in [false, true]) {
    testWidgets(
      'Current player freeze at ${large ? '320dp enlarged' : '360dp'} preserves playback controls and song',
      (tester) async {
        tester.view.physicalSize = Size(large ? 640 : 720, 1440);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (large) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        music.playlist.replace([a, b], 0);
        music.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.ready,
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(theme: appTheme(), home: PlayerSheet(app)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(ScoreBadge));
        await tester.pumpAndSettle();
        expect(app.scoreFrozen(a), true);
        expect(find.text('Балл зафиксирован'), findsOneWidget);
        expect(find.byTooltip('Пауза'), findsOneWidget);
        expect(music.playbackState.value.playing, true);
        expect(music.playlist.current!.id, 'a');
        expect(app.scoreFor(a), 10);
        await captureUi(
          tester,
          large ? 'score-frozen-player-320-large' : 'score-frozen-player-360',
        );
        await tester.longPress(find.byType(ScoreBadge));
        await tester.pumpAndSettle();
        expect(app.scoreFrozen(a), false);
        expect(find.text('Твой счёт'), findsOneWidget);
        expect(tester.takeException(), null);
      },
    );
  }

  testWidgets(
    'Holding the score freezes and unfreezes without playing or moving the row',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester);
      await tester.pumpAndSettle();
      final score = find.descendant(
        of: find.byType(TrackTile).last,
        matching: find.byType(ScoreBadge),
      );
      final rect = tester.getRect(score);
      await tester.longPress(score);
      await tester.pumpAndSettle();
      expect(app.scoreFrozen(a), true);
      expect(app.scoreFor(a), 10);
      expect(music.played, isEmpty);
      expect(tester.getRect(score), rect);
      final plus = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Плюс один: На своём уровне',
      );
      expect(tester.widget<IconButton>(plus).onPressed, isNull);
      expect(find.byType(SnackBar), findsNothing);
      await captureUi(tester, 'score-frozen-library-360');
      await tester.longPress(score);
      await tester.pumpAndSettle();
      expect(app.scoreFrozen(a), false);
      expect(tester.widget<IconButton>(plus).onPressed, isNotNull);
      expect(music.played, isEmpty);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'Freeze filter previews, applies, plays the visible list and resets',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await app.toggleScoreFreeze(a);
      await show(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-filter')));
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('filter-freeze-unfrozen'));
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.text('Подходит 1 трек'), findsOneWidget);
      await captureUi(tester, 'score-freeze-filter-360');
      await tester.tap(find.byKey(const Key('apply-library-filter')));
      await tester.pumpAndSettle();
      expect(app.libraryFilter.scoreFreeze, ScoreFreezeFilter.unfrozen);
      expect(app.visibleTracks.single.id, 'b');
      await tester.tap(find.byKey(const Key('play-from-top')));
      await tester.pumpAndSettle();
      expect(music.played.single.id, 'b');
      await tester.tap(find.byKey(const Key('clear-library-filter')));
      await tester.pumpAndSettle();
      expect(app.visibleTracks, hasLength(2));
      expect(app.scoreFrozen(a), true);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'Compact frozen score and filter fit 320dp with enlarged text and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1440);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await show(tester);
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(ScoreBadge).last);
      await tester.pumpAndSettle();
      await captureUi(tester, 'score-frozen-library-320-large');
      await tester.tap(find.byKey(const Key('library-filter')));
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('filter-freeze-frozen'));
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      await captureUi(tester, 'score-freeze-filter-320-large');
      await tester.tap(find.byKey(const Key('reset-filter-draft')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-library-filter')));
      await tester.pumpAndSettle();
      expect(app.libraryFilter, LibraryFilter.all);
      expect(tester.takeException(), null);
    },
  );
}
