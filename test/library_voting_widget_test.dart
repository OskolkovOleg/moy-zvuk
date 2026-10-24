import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart' hide Rating;
import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/genre_filter.dart';
import 'package:zvuk_personal/data/library_filter.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/playback_queue.dart';
import 'package:zvuk_personal/playback/sleep_timer.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/library_screen.dart';
import 'package:zvuk_personal/ui/widgets.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/catalog_carousel.dart';
import 'package:zvuk_personal/ui/catalog_detail_screen.dart';
import 'package:zvuk_personal/ui/shuffle_sheet.dart';

import 'ui_capture.dart';

class _Store implements LibraryStore {
  @override
  Future<dynamic> get(String account, String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Music implements MusicHandler {
  _Music(LibraryStore store)
    : downloads = DownloadManager(store, directory: Directory.systemTemp);
  @override
  final DownloadManager downloads;
  @override
  final revision = ValueNotifier<int>(0);
  @override
  final error = ValueNotifier<String?>(null);
  @override
  final playlist = PlaybackQueue();
  @override
  AudioPreferences get audioPreferences => const AudioPreferences();
  @override
  AudioServiceRepeatMode get repeatMode => AudioServiceRepeatMode.none;
  @override
  final sleepTimer = SleepTimerState();
  @override
  Future<void> Function(String account, Track track, int delta)?
  onNotificationVote;
  List<Track> played = [];
  int playedIndex = -1;
  bool lastShuffled = false;
  String lastTitle = '';
  @override
  Future<void> playList(
    List<Track> tracks,
    int index, {
    String title = 'Очередь',
    bool shuffled = false,
  }) async {
    played = List.of(tracks);
    playedIndex = index;
    lastShuffled = shuffled;
    lastTitle = title;
  }

  @override
  Future<void> savePosition() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Persistence is covered by collection_controller_test. This fixture keeps UI
// taps synchronous so the regression checks the actual on-screen hit target.
class _App extends AppController {
  _App(super.store, super.music);
  @override
  Future<String> vote(Track track, int delta) async {
    ratings = {
      ...ratings,
      track.id: Rating(
        scoreFor(track) + delta,
        (ratings[track.id]?.count ?? 0) + 1,
      ),
    };
    notifyListeners();
    return 'fixture';
  }
}

void main() {
  setUpAll(loadUiFonts);
  const a = Track(id: 'a', title: 'Первая');
  const b = Track(id: 'b', title: 'Вторая');
  late _App app;
  late _Music music;
  setUp(() {
    final store = _Store();
    music = _Music(store);
    app = _App(store, music)
      ..account = const Account('owner', 'Owner')
      ..tracks = [a, b];
  });
  tearDown(() {
    app.dispose();
    music.downloads.dispose();
    music.revision.dispose();
    music.error.dispose();
  });
  List<String> rows(WidgetTester tester) => tester
      .widgetList<TrackTile>(find.byType(TrackTile))
      .map((tile) => tile.track.id)
      .toList();

  testWidgets(
    'Library applies rock and score filters; both play actions use that exact result',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const rock = [TrackGenre(id: 'r', name: 'Rock')];
      const pop = [TrackGenre(id: 'p', name: 'Pop')];
      const low = Track(id: 'low', title: 'Рок — 9', genres: rock);
      const middle = Track(id: 'middle', title: 'Рок — 10', genres: rock);
      const high = Track(id: 'high', title: 'Рок — 13', genres: rock);
      const other = Track(id: 'pop', title: 'Поп — 12', genres: pop);
      for (final (width, scale, suffix) in [
        (360.0, 1.0, 'normal'),
        (320.0, 1.6, 'large'),
      ]) {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        app.tracks = [low, other, middle, high];
        app.ratings = {
          'middle': const Rating(10, 1),
          'high': const Rating(13, 4),
          'pop': const Rating(12, 3),
        };
        await tester.pumpWidget(
          RepaintBoundary(key: captureKey, child: ZvukApp(app)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('library-filter')));
        await tester.pumpAndSettle();
        tester
            .widget<RangeSlider>(find.byKey(const Key('shuffle-score-slider')))
            .onChanged!(const RangeValues(10, 13));
        await tester.pumpAndSettle();
        final rockChip = find.byKey(const ValueKey('shuffle-genre-rock'));
        await tester.ensureVisible(rockChip);
        await tester.tap(rockChip);
        await tester.pumpAndSettle();
        expect(find.text('Подходит 2 трека'), findsOneWidget);
        expect(app.libraryFilter, LibraryFilter.all);
        final apply = find.byKey(const Key('apply-library-filter'));
        expect(apply.hitTestable(), findsOneWidget);
        await captureUi(tester, 'library-filter-sheet-$suffix');
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(rows(tester), ['high', 'middle']);
        expect(find.text('2 из 4 треков'), findsOneWidget);
        expect(
          app.libraryFilter,
          LibraryFilter(minScore: 10, maxScore: 13, genres: {GenreGroup.rock}),
        );
        await captureUi(tester, 'library-filtered-$suffix');
        await tester.tap(find.text(middle.title));
        await tester.pumpAndSettle();
        expect(music.played.map((t) => t.id), ['high', 'middle']);
        expect(music.playedIndex, 1);
        await tester.tap(find.byKey(const Key('play-from-top')));
        await tester.pumpAndSettle();
        expect(music.played.map((t) => t.id), ['high', 'middle']);
        expect(music.playedIndex, 0);
        await tester.tap(find.byKey(const Key('shuffle-list')));
        await tester.pumpAndSettle();
        expect(music.played.map((t) => t.id).toSet(), {'high', 'middle'});
        expect(music.lastShuffled, true);
        expect(music.lastTitle, 'Мои песни · Рок · 10–13 баллов');
        final queue = music.played.map((t) => t.id).toList();
        await app.vote(middle, -1);
        await app.vote(low, 1);
        await tester.pumpAndSettle();
        expect(rows(tester), ['high', 'middle']);
        expect(app.positionFor(middle)!.total, 4);
        await tester.tap(find.byTooltip('Обновить библиотеку'));
        await tester.pumpAndSettle();
        expect(rows(tester), ['high', 'low']);
        await tester.tap(find.byKey(const Key('clear-library-filter')));
        await tester.pumpAndSettle();
        expect(rows(tester), ['high', 'pop', 'low', 'middle']);
        expect(app.libraryFilter, LibraryFilter.all);
        expect(music.played.map((t) => t.id), queue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'Empty filters can be cleared; cancelling a reset draft keeps the active filter',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      app.tracks = [
        const Track(
          id: 'rock',
          title: 'Рок',
          genres: [TrackGenre(id: 'r', name: 'Rock')],
        ),
      ];
      final filter = LibraryFilter(
        minScore: 100,
        maxScore: 200,
        genres: {GenreGroup.rock},
      );
      app.setLibraryFilter(filter);
      await tester.pumpWidget(
        RepaintBoundary(key: captureKey, child: ZvukApp(app)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Нет подходящих песен'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('play-from-top')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('shuffle-list')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('library-filter')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RangeSlider>(find.byKey(const Key('shuffle-score-slider')))
            .values,
        const RangeValues(100, 200),
      );
      await tester.tap(find.byKey(const Key('reset-filter-draft')));
      await tester.pumpAndSettle();
      expect(find.text('Подходит 1 трек'), findsOneWidget);
      Navigator.of(tester.element(find.byType(ShuffleSheet))).pop();
      await tester.pumpAndSettle();
      expect(app.libraryFilter, filter);
      await tester.tap(find.byKey(const Key('clear-library-filter')));
      await tester.pumpAndSettle();
      expect(app.visibleTracks.single.id, 'rock');
      expect(music.played, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Back to top returns from the end without refreshing or sorting',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      app.tracks = List.generate(
        800,
        (i) => Track(id: '$i', title: 'Песня $i', artists: 'Исполнитель'),
      );
      await tester.pumpWidget(
        RepaintBoundary(key: captureKey, child: ZvukApp(app)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-back-to-top')), findsNothing);
      final first = app.tracks.first;
      await app.vote(first, -1);
      await tester.pumpAndSettle();
      final order = app.visibleTracks.map((t) => t.id).toList();
      await captureUi(tester, 'library');
      final scrollView = find.byType(CustomScrollView).first;
      await tester.drag(scrollView, const Offset(0, -1000));
      await tester.pumpAndSettle();
      final scroll = tester.widget<CustomScrollView>(scrollView).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final top = find.byKey(const Key('library-back-to-top'));
      expect(top.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(top).dy,
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
      await captureUi(tester, 'library-scrolled');
      await tester.tap(top);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(top, findsNothing);
      expect(
        find.byKey(const Key('play-from-top')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shuffle-list')).hitTestable(),
        findsOneWidget,
      );
      expect(app.visibleTracks.map((t) => t.id), order);
      expect(app.scoreFor(first), 8);
      expect(music.played, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Library and settings fit a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    app.tracks = [
      const Track(
        id: 'long',
        title: 'Очень длинное название любимой песни',
        artists: 'Название группы и второй исполнитель',
      ),
    ];
    await tester.pumpWidget(
      RepaintBoundary(key: captureKey, child: ZvukApp(app)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(TrackTile).first).height,
      lessThanOrEqualTo(90),
    );
    expect(
      tester
          .getSize(find.byTooltip('Плюс один: ${app.tracks.first.title}'))
          .width,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
    await captureUi(tester, 'library-large-text');
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Воспроизведение'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureUi(tester, 'settings-large-text');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Cover shelves preserve tap targets and long titles at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final items = [
        const CatalogItem(
          id: 'p',
          title: 'Музыка для долгой дороги домой',
          kind: CatalogKind.playlist,
          subtitle: 'Знакомые песни и новые открытия',
        ),
        const CatalogItem(
          id: 'a',
          title: 'Новые имена',
          kind: CatalogKind.album,
        ),
      ];
      CatalogItem? opened;
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            home: Scaffold(
              body: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Для тебя',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CatalogCarousel(
                      items: items,
                      onOpen: (item) => opened = item,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureUi(tester, 'covers-large-text');
      await tester.tap(find.text(items.first.title));
      expect(opened?.id, 'p');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Only the artist name opens the artist; the rest plays the song',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const track = Track(
        id: 'tap-target',
        title: 'Песня с длинным названием',
        artists: 'Я',
        artistIds: ['artist'],
        artistNames: ['Я'],
      );
      app.tracks = [track];
      for (final (width, scale) in [(360.0, 1.0), (320.0, 1.6)]) {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        var plays = 0, actions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: Center(
                child: TrackTile(
                  track: track,
                  app: app,
                  onPlay: () => plays++,
                  onActions: () => actions++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final art = tester.getRect(find.byType(Artwork));
        final ratings = tester.getRect(find.byType(RatingControls));
        final artist = find.text(track.artists);
        final points = [
          art.center,
          tester.getCenter(find.text(track.title)),
          Offset(art.right + 5, art.center.dy),
          // Same line as the artist, but in the empty space after its name.
          Offset(ratings.left - 4, tester.getCenter(artist).dy),
        ];
        for (var i = 0; i < points.length; i++) {
          await tester.tapAt(points[i]);
          await tester.pumpAndSettle();
          expect(plays, i + 1);
          expect(find.byType(CatalogDetailScreen), findsNothing);
        }
        await tester.tap(find.byTooltip('Плюс один: ${track.title}'));
        await tester.pumpAndSettle();
        expect(app.scoreFor(track), 10);
        await tester.tap(find.byTooltip('Минус один: ${track.title}'));
        await tester.pumpAndSettle();
        expect(app.scoreFor(track), 9);
        expect(plays, points.length);
        await tester.longPress(find.text(track.title));
        await tester.pumpAndSettle();
        expect(actions, 1);
        expect(plays, points.length);
        await tester.tap(artist);
        await tester.pumpAndSettle();
        expect(find.byType(CatalogDetailScreen), findsOneWidget);
        expect(
          tester
              .widget<CatalogDetailScreen>(find.byType(CatalogDetailScreen))
              .item
              .id,
          'artist',
        );
        expect(plays, points.length);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('Repeated taps at the same point keep targeting the same song', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ZvukApp(app));
    await tester.pumpAndSettle();
    final plus = find.byTooltip('Плюс один: ${b.title}');
    final point = tester.getCenter(plus);
    for (var i = 0; i < 5; i++) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(tester.getCenter(plus), point);
      expect(rows(tester), ['a', 'b']);
    }
    expect(app.scoreFor(b), 14);
    expect(find.text('14'), findsOneWidget);
    expect(app.scoreFor(a), 9);
    expect(app.positionFor(b)!.label, '1');
    await tester.tap(find.text(b.title));
    await tester.pumpAndSettle();
    expect(music.played.map((t) => t.id), ['a', 'b']);
    expect(music.played[music.playedIndex].id, 'b');
    await tester.tap(find.byKey(const Key('play-from-top')));
    await tester.pumpAndSettle();
    expect(music.played.first.id, 'a');
    expect(music.playedIndex, 0);
    await tester.tap(find.byTooltip('Обновить библиотеку'));
    await tester.pumpAndSettle();
    expect(rows(tester), ['b', 'a']);
    final minus = find.byTooltip('Минус один: ${b.title}');
    final minusPoint = tester.getCenter(minus);
    for (var i = 0; i < 8; i++) {
      await tester.tapAt(minusPoint);
      await tester.pumpAndSettle();
      expect(tester.getCenter(minus), minusPoint);
      expect(rows(tester), ['b', 'a']);
    }
    expect(app.scoreFor(b), 6);
    expect(find.text('6'), findsOneWidget);
    expect(app.scoreFor(a), 9);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 350),
    );
    await tester.pumpAndSettle();
    expect(rows(tester), ['a', 'b']);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Library return and resume sort; dismissing a dialog does not', (
    tester,
  ) async {
    await tester.pumpWidget(ZvukApp(app));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(LibraryScreen));
    final navigator = Navigator.of(context);
    await app.vote(b, 1);
    await tester.pumpAndSettle();
    expect(rows(tester), ['a', 'b']);
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Fixture')),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(rows(tester), ['a', 'b']);
    final page = navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Fixture page')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    await page;
    expect(rows(tester), ['b', 'a']);
    await app.vote(a, 1);
    await app.vote(a, 1);
    await tester.pumpAndSettle();
    expect(rows(tester), ['b', 'a']);
    await tester.tap(find.text('Плейлисты').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Библиотека'));
    await tester.pumpAndSettle();
    expect(rows(tester), ['a', 'b']);
    await app.vote(b, 1);
    await app.vote(b, 1);
    await tester.pumpAndSettle();
    expect(rows(tester), ['a', 'b']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(rows(tester), ['b', 'a']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
