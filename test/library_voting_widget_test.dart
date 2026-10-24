import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/playback_queue.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/library_screen.dart';
import 'package:zvuk_personal/ui/widgets.dart';

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
  Future<void> Function(String account, Track track, int delta)?
  onNotificationVote;
  List<Track> played = [];
  int playedIndex = -1;
  @override
  Future<void> playList(
    List<Track> tracks,
    int index, {
    String title = 'Очередь',
    bool shuffled = false,
  }) async {
    played = List.of(tracks);
    playedIndex = index;
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
