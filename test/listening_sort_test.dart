import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/history_store.dart';
import 'package:zvuk_personal/data/library_display_order.dart';
import 'package:zvuk_personal/data/library_filter.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/listening_stats.dart';
import 'package:zvuk_personal/data/listening_stats_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/personal_models.dart';

import 'collection_controller_test.dart' show UnusedMusic;

void main() {
  const a = Track(id: 'a', title: 'A'),
      b = Track(id: 'b', title: 'B'),
      c = Track(id: 'c', title: 'C');
  final now = DateTime.utc(2026, 11, 7, 12);
  test(
    'Oldest orders real dates first; unknown is not an invented old date',
    () {
      final stats = ListeningStats(
        now,
        last: {'a': now, 'b': now.subtract(const Duration(days: 30))},
      );
      expect(
        sortedLibraryTracks(
          [a, c, b],
          {},
          sort: LibrarySort.oldest,
          stats: stats,
        ).map((t) => t.id),
        ['b', 'a', 'c'],
      );
    },
  );
  test('Frequency uses a rolling seven day window, excludes future dates, and uses dates for ties', () {
    final stats = ListeningStats(
      now.subtract(const Duration(days: 30)),
      last: {'b': now, 'c': now.subtract(const Duration(days: 10))},
      starts: [
        for (var i = 0; i < 20; i++)
          ListeningStart('old$i', 'a', now.subtract(const Duration(days: 8))),
        ListeningStart('1', 'b', now.subtract(const Duration(days: 1))),
        ListeningStart('2', 'b', now.subtract(const Duration(days: 2))),
        ListeningStart('3', 'c', now.subtract(const Duration(days: 3))),
        ListeningStart('future', 'a', now.add(const Duration(hours: 1))),
      ],
    );
    expect(stats.weeklyCount('a', now), 0);
    expect(
      sortedLibraryTracks(
        [b, c, a],
        {},
        sort: LibrarySort.leastPlayed,
        stats: stats,
        now: now,
      ).map((t) => t.id),
      ['a', 'c', 'b'],
    );
    expect(stats.fullWeek(now), true);
    expect(ListeningStats(now).fullWeek(now), false);
  });
  test('History changes and votes keep rows fixed until refresh; filter intersects sorting', () {
    final order = LibraryDisplayOrder(),
        scores = {
          'a': const Rating(10, 1),
          'b': const Rating(12, 3),
          'c': const Rating(8, 1),
        };
    final stats = ListeningStats(
      now,
      last: {'a': now, 'b': now.subtract(const Duration(days: 5))},
    );
    final filter = LibraryFilter(minScore: 10, maxScore: 13);
    List<String> rows() => order
        .arrange(
          'a',
          'favorites',
          [a, b, c],
          scores,
          filter: filter,
          sort: LibrarySort.oldest,
          stats: stats,
        )
        .map((t) => t.id)
        .toList();
    expect(rows(), ['b', 'a']);
    stats.last['b'] = now.add(const Duration(hours: 1));
    scores['b'] = const Rating(14, 5);
    expect(rows(), ['b', 'a']);
    order.reset();
    expect(rows(), ['a']);
  });
  test(
    'Occurrence IDs survive retry/resume but change on a new entry or replay',
    () {
      final state = ListeningOccurrence();
      final first = state.idFor(1);
      expect(state.idFor(1), first);
      expect(state.idFor(2), isNot(first));
      expect(state.idFor(1), isNot(first));
      final before = state.idFor(1);
      state.reset();
      expect(state.idFor(1), isNot(before));
    },
  );
  group('Durable listening statistics', () {
    late LibraryStore store;
    late Directory directory;
    setUp(() async {
      sqfliteFfiInit();
      directory = await Directory.systemTemp.createTemp('listening-test');
      store = await LibraryStore.open(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/test.db',
      );
    });
    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    test(
      'Legacy history seeds last dates, never fabricated frequency counts',
      () async {
        await store.put('a', 'listening-history', [
          {
            'track': a.toJson(),
            'at': now.subtract(const Duration(days: 20)).toIso8601String(),
          },
        ]);
        final stats = await ListeningStatsStore(store).load('a', now: now);
        expect(stats.last['a'], now.subtract(const Duration(days: 20)));
        expect(stats.starts, isEmpty);
        expect(stats.since, now);
      },
    );
    test('Transactional starts retain all last dates beyond 200, deduplicate retries and isolate accounts', () async {
      final history = HistoryStore(store),
          statsStore = ListeningStatsStore(store);
      for (var i = 0; i < 205; i++) {
        await history.record(
          'a',
          Track(id: '$i', title: 'Fixture'),
          now,
          eventId: '$i',
        );
      }
      await history.record(
        'a',
        const Track(id: '0', title: 'Retry'),
        now,
        eventId: '0',
      );
      var stats = await statsStore.load('a', now: now);
      expect(stats.starts.length, 205);
      expect(stats.last.length, 205);
      expect((await history.recent('a')).length, 200);
      expect((await statsStore.load('b', now: now)).starts, isEmpty);
      stats = await statsStore.load('a', now: now.add(const Duration(days: 9)));
      expect(stats.starts, isEmpty);
      expect(stats.last.length, 205);
    });
    test(
      'Server dates never inflate weekly counts or overwrite newer local dates',
      () async {
        await HistoryStore(store).record('a', a, now);
        await ListeningStatsStore(store).mergeDates('a', [
          ListeningEntry(a, now.subtract(const Duration(days: 1))),
          ListeningEntry(b, now.subtract(const Duration(days: 2))),
        ]);
        final stats = await ListeningStatsStore(store).load('a', now: now);
        expect(stats.weeklyCount('a', now), 1);
        expect(stats.last['a'], now);
        expect(stats.last['b'], now.subtract(const Duration(days: 2)));
        expect(stats.weeklyCount('b', now), 0);
      },
    );
    test('Controller plays the filtered sorted snapshot and keeps it stable after a vote', () async {
      final music = UnusedMusic();
      final app = AppController(store, music)
        ..account = const Account('a', 'Fixture')
        ..tracks = [a, b, c]
        ..favoriteTracks = [a, b, c];
      await store.saveTracks('a', 'favorites', [a, b, c]);
      await HistoryStore(store)
          .record('a', b, DateTime.now().subtract(const Duration(days: 2)));
      await HistoryStore(store)
          .record('a', a, DateTime.now().subtract(const Duration(days: 1)));
      await app.setLibrarySort(LibrarySort.oldest);
      expect(app.visibleTracks.map((t) => t.id), ['b', 'a', 'c']);
      await app.playVisible();
      expect(music.played.map((t) => t.id), ['b', 'a', 'c']);
      await app.vote(b, 1);
      expect(app.visibleTracks.map((t) => t.id), ['b', 'a', 'c']);
      app.account = const Account('b', 'Other');
      expect(app.librarySort, LibrarySort.scores);
      expect(app.listeningStats, null);
      app.dispose();
    });
  });
}
