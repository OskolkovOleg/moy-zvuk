import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/discovery_models.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/discovery_controller.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/playback_queue.dart';
import 'package:zvuk_personal/ui/discovery_entry.dart';
import 'package:zvuk_personal/ui/discovery_screen.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/widgets.dart';

import 'ui_capture.dart';

class _Store implements LibraryStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  int plays = 0, appends = 0;
  bool shuffled = false;
  List<Track> last = [];
  @override
  Future<void> playList(
    List<Track> tracks,
    int index, {
    String title = 'Queue',
    bool shuffled = false,
  }) async {
    plays++;
    last = tracks;
    this.shuffled = shuffled;
  }

  @override
  Future<int> appendDiscoveries(List<Track> tracks) async {
    appends++;
    last = tracks;
    return tracks.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _App extends AppController {
  _App(super.store, super.music);
  @override
  Future<String> vote(Track track, int delta) async {
    ratings = {...ratings, track.id: Rating(scoreFor(track) + delta, 1)};
    if (delta > 0 && !isFavorite(track.id)) favoriteTracks.add(track);
    notifyListeners();
    return 'fixture';
  }
}

class _Discovery extends DiscoveryController {
  _Discovery(super.app, super.mode);
  @override
  Future<void> load({bool resetRecent = false}) async {
    notifyListeners();
  }
}

const fixture = [
  DiscoveryCandidate(
    Track(
      id: '1',
      title: 'Музыка для танцпола',
      artists: 'Первый исполнитель',
      explicit: false,
    ),
    'Клубная музыка | Лучшее',
  ),
  DiscoveryCandidate(
    Track(
      id: '2',
      title: 'Совсем другое звучание',
      artists: 'Второй исполнитель',
      explicit: false,
    ),
    'Рок | Классические хиты',
  ),
];
void main() {
  setUpAll(loadUiFonts);
  late _App app;
  late _Music music;
  final controllers = <_Discovery>[];
  setUp(() {
    final store = _Store();
    music = _Music(store);
    app = _App(store, music)..account = const Account('owner', 'Fixture');
  });
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    app.dispose();
    music.downloads.dispose();
    music.error.dispose();
    music.revision.dispose();
  });
  Future<_Discovery> show(
    WidgetTester tester,
    DiscoveryMode mode, {
    bool empty = false,
  }) async {
    final c = _Discovery(app, mode)..candidates = empty ? [] : List.of(fixture);
    controllers.add(c);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: RepaintBoundary(
          key: captureKey,
          child: DiscoveryScreen(app, mode, controller: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('All four entry modes describe distinct discovery jobs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            key: captureKey,
            child: ListView(children: [DiscoveryEntries(app)]),
          ),
        ),
      ),
    );
    for (final mode in DiscoveryMode.values) {
      expect(find.text(mode.label), findsOneWidget);
    }
    await captureUi(tester, 'discovery-hub-360');
    expect(tester.takeException(), null);
  });
  testWidgets(
    'Queue, play and shuffle are separate; votes do not remove or move discovery rows',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, DiscoveryMode.best);
      expect(music.plays, 0);
      await tester.tap(find.text('В очередь'));
      await tester.pumpAndSettle();
      expect(music.appends, 1);
      expect(music.plays, 0);
      await tester.tap(find.byTooltip('Плюс один: Музыка для танцпола'));
      await tester.pumpAndSettle();
      expect(app.scoreFor(fixture.first.track), 10);
      expect(app.isFavorite('1'), true);
      expect(
        tester
            .widgetList<TrackTile>(find.byType(TrackTile))
            .map((t) => t.track.id),
        ['1', '2'],
      );
      await tester.tap(find.text('Слушать'));
      await tester.pumpAndSettle();
      expect(music.plays, 1);
      expect(music.last.map((t) => t.id), ['1', '2']);
      await tester.tap(find.text('Перемешать'));
      await tester.pumpAndSettle();
      expect(music.plays, 2);
      expect(music.shuffled, true);
    },
  );
  testWidgets(
    'Explore has real source directions, captions and no personal-wave switch',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await show(tester, DiscoveryMode.explore);
      expect(find.text('Клубная'), findsOneWidget);
      await tester.tap(find.text('Клубная'));
      await tester.pumpAndSettle();
      expect(c.direction, 'club');
      expect(find.text('Мой поток'), findsNothing);
      await captureUi(tester, 'discovery-explore-360');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await captureUi(tester, 'discovery-explore-tracks-360');
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'Narrow explore layout with large text scrolls without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1440);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(tester, DiscoveryMode.explore);
      await captureUi(tester, 'discovery-explore-320-large');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
      await tester.pumpAndSettle();
      await captureUi(tester, 'discovery-explore-320-large-tracks');
      expect(tester.takeException(), null);
    },
  );
  testWidgets('Empty discovery explains repeats and offers an explicit reset', (
    tester,
  ) async {
    final c = await show(tester, DiscoveryMode.best, empty: true);
    expect(find.text('Свежих предложений пока нет'), findsOneWidget);
    expect(find.text('Повторить предложения'), findsOneWidget);
    c.error = 'Ошибка источника';
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Ошибка источника'), findsOneWidget);
    expect(find.text('Свежих предложений пока нет'), findsNothing);
  });
}
