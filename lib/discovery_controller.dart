import 'package:flutter/foundation.dart';

import 'app_controller.dart';
import 'data/catalog_models.dart';
import 'data/discovery_models.dart';
import 'data/discovery_store.dart';
import 'data/models.dart';
import 'data/wave_source.dart';
import 'data/zvuk_api.dart';

class DiscoveryController extends ChangeNotifier {
  DiscoveryController(
    this.app,
    this.mode, {
    this.seed,
    DiscoveryStore? memory,
    DateTime Function()? now,
  }) : memory = memory ?? DiscoveryStore(app.store),
       _now = now ?? DateTime.now;
  final AppController app;
  final DiscoveryMode mode;
  final DiscoveryStore memory;
  final DateTime Function() _now;
  Track? seed;
  String? direction;
  bool censoredOnly = false, loading = false;
  String? error, note;
  List<DiscoveryCandidate> candidates = [];
  int _request = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool resetRecent = false}) async {
    final request = ++_request, api = app.api, account = app.account?.id;
    if (api == null || account == null) {
      candidates = [];
      error = 'Для поиска новой музыки обнови подключение в настройках.';
      loading = false;
      _notify();
      return;
    }
    bool current() =>
        !_disposed &&
        request == _request &&
        app.api == api &&
        app.account?.id == account;
    final selectedSeed = seed,
        selectedDirection = direction,
        clean = censoredOnly;
    final library = List<Track>.of(app.favoriteTracks),
        ratings = Map<String, Rating>.of(app.ratings);
    loading = true;
    error = null;
    note = null;
    candidates = [];
    _notify();
    try {
      if (resetRecent) await memory.resetRecent(account);
      final state = await memory.load(account);
      if (!current()) return;
      final cursors = Map<String, int>.of(state.cursors);
      final failures = <String>[];
      Object? firstFailure;
      var successful = 0;
      Future<List<DiscoveryCandidate>> source(
        String name,
        Future<List<DiscoveryCandidate>> Function() fetch,
      ) async {
        try {
          final rows = await fetch();
          successful++;
          return rows;
        } catch (e) {
          firstFailure ??= e;
          failures.add(name);
          return [];
        }
      }

      Future<List<DiscoveryCandidate>> radio(Track song) =>
          source(song.title, () async {
            final page = await api.recommendations(
              WaveSource.fromTrack(song),
              cursor: cursors[song.id] ?? 0,
              count: 50,
            );
            cursors[song.id] = page.cursor;
            return page.tracks
                .map(
                  (t) => DiscoveryCandidate(
                    t,
                    'По треку «${song.title}»',
                    source: CatalogItem(
                      id: song.id,
                      title: song.title,
                      kind: CatalogKind.track,
                    ),
                  ),
                )
                .toList();
          });
      late List<List<DiscoveryCandidate>> pools;
      switch (mode) {
        case DiscoveryMode.best:
          final seeds = discoverySeeds(
            library,
            ratings,
            offset: state.cycle * 5,
          );
          if (seeds.isEmpty) {
            throw const ZvukException(
              'Добавь несколько песен в библиотеку, чтобы искать по ним новое.',
            );
          }
          pools = await Future.wait(seeds.map(radio));
        case DiscoveryMode.song:
          if (selectedSeed == null) {
            throw const ZvukException(
              'Выбери песню, настроение которой хочется продолжить.',
            );
          }
          pools = [await radio(selectedSeed)];
        case DiscoveryMode.releases:
          final artists = <String>{
            ...app.savedCatalogItems
                .where((i) => i.kind == CatalogKind.artist)
                .map((i) => i.id),
            ...discoverySeeds(
              library,
              ratings,
              offset: state.cycle * 5,
              limit: 12,
            ).expand((t) => t.artistIds),
          }.toList();
          if (artists.isEmpty) {
            throw const ZvukException(
              'Добавь любимых артистов или песни в библиотеку — здесь появятся их новинки.',
            );
          }
          pools = [
            await source('Новинки артистов', () async {
              final offset = state.cycle * 12 % artists.length;
              final batch = [
                ...artists.skip(offset),
                ...artists.take(offset),
              ].take(12).toList();
              final albums = await api.discoveryReleases(batch);
              return [
                for (final release in albums)
                  if (isRecentRelease(release.date, _now()))
                    for (final track in release.tracks)
                      DiscoveryCandidate(
                        track,
                        '${_date(release.date!)} · ${release.album.title}',
                        source: release.album,
                      ),
              ];
            }),
          ];
        case DiscoveryMode.explore:
          final ids = selectedDirection == null
              ? [
                  '1062105',
                  ...discoveryDirections.expand((d) => d.playlistIds.take(1)),
                ]
              : discoveryDirections
                    .firstWhere((d) => d.id == selectedDirection)
                    .playlistIds;
          final lists = await api.getPlaylists(ids);
          if (lists.length < ids.length) failures.add('Недоступная подборка');
          if (!current()) return;
          pools = await Future.wait(
            lists.map(
              (list) => source(list.title, () async {
                final tracks = await api.playlistTracks(list.id);
                return tracks
                    .map(
                      (t) => DiscoveryCandidate(
                        t,
                        list.title,
                        source: CatalogItem.playlist(list),
                      ),
                    )
                    .toList();
              }),
            ),
          );
      }
      if (!current()) return;
      if (successful == 0) {
        if (firstFailure is ZvukException) throw firstFailure!;
        throw const ZvukException(
          'Источники музыки сейчас недоступны. Попробуй ещё раз.',
        );
      }
      final found = selectDiscoveries(
        pools,
        library: library,
        excluded: state.excluded(_now()),
        censoredOnly: clean,
      );
      // Recheck current favorites: a vote during the network request may add one.
      candidates = selectDiscoveries(
        [found],
        library: app.favoriteTracks,
        censoredOnly: clean,
      );
      if (failures.isNotEmpty) {
        note = 'Часть источников недоступна. Остальные загружены.';
      }
      await memory.offered(
        account,
        candidates.map((c) => c.track).toList(),
        _now(),
        cursors: cursors,
      );
      if (!current()) return;
    } catch (e) {
      if (current()) {
        error = e is ZvukException
            ? e.message
            : 'Не удалось подобрать музыку. Попробуй ещё раз.';
        candidates = [];
      }
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        if (!current()) {
          candidates = [];
          error = 'Подключение изменилось. Открой подборку заново.';
        }
        _notify();
      }
    }
  }

  Future<void> hide(Track track) async {
    final account = app.account?.id;
    if (account == null) return;
    await memory.hide(account, track);
    if (_disposed || app.account?.id != account) return;
    final keys = discoveryIdentity(track);
    candidates = candidates
        .where((c) => !discoveryIdentity(c.track).any(keys.contains))
        .toList();
    _notify();
  }
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
