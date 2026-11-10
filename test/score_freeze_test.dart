import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/genre_filter.dart';
import 'package:zvuk_personal/data/library_filter.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/music_handler.dart';

class _Music implements MusicHandler {
  List<Track> played = [];
  @override
  Future<void> Function(String, Track, int)? onNotificationVote;
  @override
  void setNotificationRatings(String account, Map<String, Rating> ratings) {}
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

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  const a = Track(
    id: 'a',
    title: 'Точно на своём уровне',
    genres: [TrackGenre(id: 'rock', name: 'Rock')],
    explicit: false,
  );
  const b = Track(
    id: 'b',
    title: 'Ещё переслушать',
    genres: [TrackGenre(id: 'rock', name: 'Rock')],
    explicit: false,
  );
  const c = Track(
    id: 'c',
    title: 'Другая песня',
    genres: [TrackGenre(id: 'pop', name: 'Pop')],
    explicit: true,
  );
  Future<LibraryStore> open(String name) => LibraryStore.open(
    factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
    databasePath: '${directory.path}/$name.db',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-score-freeze');
    store = await open('library');
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'Freeze survives restart, protects votes and undo, and isolates accounts',
    () async {
      final event = await store.vote('owner', a, 1, addToLibrary: true);
      expect(await store.toggleScoreFreeze('owner', a.id), true);
      for (final delta in [-1, 1]) {
        await expectLater(
          store.vote('owner', a, delta),
          throwsA(isA<ScoreFrozenException>()),
        );
      }
      await expectLater(
        store.undo('owner', event),
        throwsA(isA<ScoreFrozenException>()),
      );
      expect(
        (jsonDecode(await store.exportRatings('owner'))['events'] as List),
        hasLength(1),
      );
      await store.close();
      store = await open('library');
      final rating = (await store.ratings('owner'))[a.id]!;
      expect(rating.frozen, true);
      expect(rating.score, 10);
      expect(rating.count, 1);
      expect((await store.loadTracks('owner', 'favorites')).single.id, a.id);
      await store.vote('other', a, -1);
      expect((await store.ratings('other'))[a.id]!.frozen, false);
      expect((await store.ratings('other'))[a.id]!.score, 8);
      expect(await store.toggleScoreFreeze('owner', a.id), false);
      await store.vote('owner', a, 1);
      expect((await store.ratings('owner'))[a.id]!.score, 11);
    },
  );

  test('Freezing an unrated discovery preserves 9 and does not add it or create votes', () async {
    await store.toggleScoreFreeze('owner', b.id);
    final rating = (await store.ratings('owner'))[b.id]!;
    expect(rating.score, 9);
    expect(rating.count, 0);
    expect(rating.frozen, true);
    expect(await store.loadTracks('owner', 'favorites'), isEmpty);
    final backup = jsonDecode(await store.exportRatings('owner'));
    expect(backup['events'], isEmpty);
    expect(backup['baselines'], isEmpty);
    expect(backup['frozenTracks'], ['b']);
  });

  test('Concurrent freeze and a stale vote serialize atomically', () async {
    final freeze = store.toggleScoreFreeze('owner', a.id);
    final vote = store.vote('owner', a, 1, addToLibrary: true);
    await expectLater(vote, throwsA(isA<ScoreFrozenException>()));
    expect(await freeze, true);
    expect((await store.ratings('owner'))[a.id]!.score, 9);
    expect(await store.loadTracks('owner', 'favorites'), isEmpty);
    await Future.wait(
      List.generate(10, (_) => store.toggleScoreFreeze('owner', a.id)),
    );
    expect((await store.ratings('owner'))[a.id]!.frozen, true);
  });

  test('Backup restores flags, legacy import preserves them, malformed flags roll back', () async {
    await store.vote('owner', a, 1);
    await store.toggleScoreFreeze('owner', a.id);
    await store.toggleScoreFreeze('owner', b.id);
    final backup = await store.exportRatings('owner');
    final restored = await open('restored');
    try {
      expect(await restored.importRatings('owner', backup), 1);
      expect(await restored.importRatings('owner', backup), 0);
      expect(
        (await restored.ratings('owner')).values.every((r) => r.frozen),
        true,
      );
      expect((await restored.ratings('owner'))[a.id]!.score, 10);
      final legacy = jsonDecode(backup) as Map<String, dynamic>;
      legacy.remove('frozenTracks');
      await restored.importRatings('owner', jsonEncode(legacy));
      expect((await restored.ratings('owner'))[a.id]!.frozen, true);
      final before = await restored.exportRatings('owner');
      legacy['frozenTracks'] = ['a', 3];
      await expectLater(
        restored.importRatings('owner', jsonEncode(legacy)),
        throwsFormatException,
      );
      expect(await restored.exportRatings('owner'), before);
      await expectLater(
        restored.importRatings('other', backup),
        throwsFormatException,
      );
    } finally {
      await restored.close();
    }
  });

  test('Review filter intersects score, genre and content; freezing never changes current queue', () async {
    await store.saveTracks('owner', 'favorites', [a, b, c]);
    for (final t in [a, b, c]) {
      await store.vote('owner', t, 1);
    }
    final music = _Music();
    final app = AppController(store, music)
      ..account = const Account('owner', 'Fixture')
      ..tracks = [a, b, c]
      ..favoriteTracks = [a, b, c]
      ..ratings = await store.ratings('owner');
    try {
      final filter = LibraryFilter(
        minScore: 10,
        maxScore: 13,
        genres: {GenreGroup.rock},
        censoredOnly: true,
        scoreFreeze: ScoreFreezeFilter.unfrozen,
      );
      app.setLibraryFilter(filter);
      expect(app.visibleTracks.map((t) => t.id), ['a', 'b']);
      await app.playVisible();
      await app.toggleScoreFreeze(a);
      expect(app.visibleTracks.map((t) => t.id), ['b']);
      expect(music.played.map((t) => t.id), ['a', 'b']);
      expect(app.scoreFor(a), 10);
      await expectLater(
        music.onNotificationVote!('owner', a, -1),
        throwsA(isA<ScoreFrozenException>()),
      );
      expect(app.scoreFor(a), 10);
      await app.playVisible();
      expect(music.played.map((t) => t.id), ['b']);
      app.setLibraryFilter(
        LibraryFilter(scoreFreeze: ScoreFreezeFilter.frozen),
      );
      expect(app.visibleTracks.single.id, 'a');
      await app.toggleScoreFreeze(a);
      expect(app.visibleTracks, isEmpty);
      app.setLibraryFilter(LibraryFilter.all);
      expect(app.visibleTracks, hasLength(3));
      expect(await store.loadTracks('owner', 'favorites'), hasLength(3));
    } finally {
      app.dispose();
    }
  });

  test(
    'A queued gesture cannot freeze a song in a newly selected account',
    () async {
      final app = AppController(store, _Music())
        ..account = const Account('owner', 'Owner');
      final change = app.toggleScoreFreeze(a);
      app.account = const Account('other', 'Other');
      await expectLater(change, throwsStateError);
      expect(await store.ratings('owner'), isEmpty);
      expect(await store.ratings('other'), isEmpty);
      app.dispose();
    },
  );
}
