import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/library_filter.dart';
import 'package:zvuk_personal/data/listening_stats.dart';
import 'package:zvuk_personal/data/listening_stats_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/playback_queue.dart';
import 'package:zvuk_personal/ui/library_screen.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/widgets.dart';

import 'ui_capture.dart';

class _Store implements LibraryStore {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Stats implements ListeningStatsStore {
  _Stats(this.stats);
  final ListeningStats stats;
  @override
  Future<ListeningStats> load(String account, {DateTime? now}) async => stats;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Music implements MusicHandler {
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
  Future<void> Function(String, Track, int)? onNotificationVote;
  List<Track> played = [];
  @override
  Future<void> playList(
    List<Track> tracks,
    int index, {
    String title = 'Queue',
    bool shuffled = false,
  }) async {
    played = List.of(tracks);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() async {
    await loadUiFonts();
  });
  late LibraryStore store;
  late AppController app;
  late _Music music;
  const a = Track(id: 'a', title: 'Часто слушаю', artists: 'Первый'),
      b = Track(id: 'b', title: 'Один запуск', artists: 'Второй'),
      c = Track(id: 'c', title: 'Без запусков за неделю', artists: 'Третий');
  setUp(() async {
    store = _Store();
    final now = DateTime.now();
    final stats = ListeningStats(
      now.subtract(const Duration(days: 2)),
      last: {'a': now.subtract(const Duration(days: 1)), 'b': now},
      starts: [
        ListeningStart('a1', 'a', now.subtract(const Duration(days: 2))),
        ListeningStart('a2', 'a', now.subtract(const Duration(days: 1))),
        ListeningStart('b', 'b', now),
      ],
    );
    music = _Music(store);
    app = AppController(store, music, historyStatsStore: _Stats(stats))
      ..account = const Account('owner', 'Fixture')
      ..tracks = [a, b, c]
      ..favoriteTracks = [a, b, c]
      ..ratings = {
        'a': const Rating(13, 4),
        'b': const Rating(12, 3),
        'c': const Rating(10, 1),
      };
  });
  tearDown(() async {
    app.dispose();
    music.downloads.dispose();
    music.error.dispose();
    music.revision.dispose();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            key: captureKey,
            child: AnimatedBuilder(
              animation: app,
              builder: (_, _) => LibraryScreen(app),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Sort sits beside icon-only play and shuffle; weekly filtered snapshot plays in order',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      app.setLibraryFilter(LibraryFilter(minScore: 10, maxScore: 13));
      await show(tester);
      expect(find.text('Слушать'), findsNothing);
      final play = tester.getRect(find.byKey(const Key('play-from-top')));
      final sort = tester.getRect(find.byKey(const Key('library-sort')));
      final shuffle = tester.getRect(find.byKey(const Key('shuffle-list')));
      expect(sort.center.dy, play.center.dy);
      expect(shuffle.center.dy, play.center.dy);
      await tester.tap(find.byKey(const Key('library-sort')));
      await tester.pumpAndSettle();
      for (final value in LibrarySort.values) {
        expect(find.text(value.label), findsOneWidget);
      }
      await captureUi(tester, 'library-sort-menu-360');
      await tester.tap(find.byKey(const ValueKey('sort-leastPlayed')));
      await tester.pumpAndSettle();
      expect(app.visibleTracks.map((t) => t.id), ['c', 'b', 'a']);
      await captureUi(tester, 'library-weekly-sort-360');
      await tester.tap(find.byKey(const Key('play-from-top')));
      await tester.pumpAndSettle();
      expect(music.played.map((t) => t.id), ['c', 'b', 'a']);
      expect(
        tester
            .widgetList<TrackTile>(find.byType(TrackTile))
            .map((t) => t.track.id),
        ['c', 'b', 'a'],
      );
      expect(tester.takeException(), null);
    },
  );
  testWidgets('Oldest summary and sort menu fit 320dp with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1440);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => app.setLibrarySort(LibrarySort.oldest));
    await show(tester);
    await captureUi(tester, 'library-oldest-320-large');
    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await captureUi(tester, 'library-sort-menu-320-large');
    expect(tester.takeException(), null);
  });
}
