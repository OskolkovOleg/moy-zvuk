import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/library_store.dart';
import 'data/models.dart';
import 'data/catalog_models.dart';
import 'data/token_store.dart';
import 'data/zvuk_api.dart';
import 'playback/music_handler.dart';
import 'playback/shuffle_tracks.dart';

part 'personal_controller.dart';

class AppController extends ChangeNotifier {
  AppController(this.store, this.music, {this.tokens = const TokenStore()}) {
    music.onNotificationVote = _voteFromNotification;
  }

  Future<void> _voteFromNotification(
    String accountId,
    Track track,
    int delta,
  ) async {
    if (account?.id != accountId) return;
    await vote(track, delta);
  }

  @override
  void dispose() {
    if (music.onNotificationVote == _voteFromNotification) {
      music.onNotificationVote = null;
    }
    super.dispose();
  }

  final LibraryStore store;
  final MusicHandler music;
  final TokenStore tokens;
  Account? account;
  ZvukApi? api;
  List<Track> tracks = [];
  List<PlaylistInfo> playlists = [];
  Map<String, Rating> ratings = {};
  List<String> manualOrder = [];
  String listId = 'favorites', listTitle = 'Любимое';
  bool busy = false, ranked = false, unrated = false, connecting = false;
  bool reordering = false;
  String? message;
  int _selection = 0, _catalogRevision = 0;
  int libraryRequests = 0;
  List<Track> favoriteTracks = [];
  List<CatalogItem> savedCatalogItems = [];
  bool savedCatalogKnown = false, savedCatalogLoading = false;
  String? savedCatalogError;
  int _savedRequest = 0;
  void _notifySavedCatalog() => notifyListeners();
  bool serverBusy = false;
  Future<void> _edits = Future.value();
  bool isFavorite(String id) => favoriteTracks.any((t) => t.id == id);
  bool owns(PlaylistInfo p) => p.ownerId != null && p.ownerId == account?.id;
  bool hasPlaylist(String id) => playlists.any((p) => p.id == id);

  int scoreFor(Track track) => trackScore(track.id, ratings);

  // Rank in the entire selected library list, independent of playback order,
  // shuffle subset, manual arrangement and the unrated filter.
  RatingPosition? positionFor(Track track) =>
      ratingPosition(tracks, ratings, track.id);

  List<Track> get visibleTracks => ranked
      ? rankedTracks(tracks, ratings, unrated: unrated)
      : manuallyOrderedTracks(tracks, manualOrder);

  Future<void> playVisible({int index = 0}) async {
    final snapshot = visibleTracks;
    if (snapshot.isEmpty) return;
    await music.playList(snapshot, index, title: listTitle);
  }

  Future<void> playShuffled({int? bestCount}) async {
    final snapshot = shuffledTracks(tracks, ratings, bestCount: bestCount);
    if (snapshot.isEmpty) return;
    await music.playList(
      snapshot,
      0,
      title: bestCount == null
          ? listTitle
          : '$listTitle · топ ${snapshot.length}',
      shuffled: true,
    );
  }

  Future<void> moveTrack(int index, int delta) async {
    if (ranked || reordering || account == null || ![-1, 1].contains(delta)) {
      return;
    }
    final ordered = visibleTracks;
    final target = index + delta;
    if (index < 0 ||
        index >= ordered.length ||
        target < 0 ||
        target >= ordered.length) {
      return;
    }
    final accountId = account!.id, selected = listId;
    final selection = _selection;
    final item = ordered[index];
    ordered[index] = ordered[target];
    ordered[target] = item;
    final ids = ordered.map((t) => t.id).toList();
    reordering = true;
    notifyListeners();
    try {
      await store.saveOrder(accountId, selected, ids);
      if (account?.id == accountId && selection == _selection) {
        manualOrder = ids;
      }
    } finally {
      reordering = false;
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    final cached = await store.get('_app', 'account');
    if (cached is Map<String, dynamic>) {
      account = Account.fromJson(cached);
      await _loadCache();
    }
    try {
      final session = await tokens.read();
      if (session != null) {
        if (account?.id != session.account.id) {
          account = session.account;
          tracks = [];
          ratings = {};
          playlists = [];
          await _loadCache();
        }
        api = ZvukApi(session.token);
      }
      if (account != null) await music.configure(account!.id, api);
      if (api != null && account != null) unawaited(refresh());
    } catch (_) {
      message = 'Не удалось прочитать подключение. Введи токен в настройках.';
    }
    notifyListeners();
  }

  Future<void> _loadCache() async {
    final id = account!.id;
    final saved = await store.get(id, 'saved-catalog');
    savedCatalogKnown = saved is List;
    savedCatalogItems = (saved as List? ?? [])
        .map((j) => CatalogItem.fromJson(j))
        .toList();
    savedCatalogError = null;
    savedCatalogLoading = false;
    favoriteTracks = await store.loadTracks(id, 'favorites');
    tracks = listId == 'favorites'
        ? favoriteTracks
        : await store.loadTracks(id, listId);
    manualOrder = await store.loadOrder(id, listId);
    ranked = await store.get(id, 'sort') == 'rating';
    ratings = await store.ratings(id);
    playlists = ((await store.get(id, 'playlists')) as List? ?? [])
        .map((j) => PlaylistInfo.fromJson(j))
        .toList();
  }

  Future<void> connect(String token) async {
    connecting = true;
    message = null;
    notifyListeners();
    final candidate = ZvukApi(token.trim());
    try {
      final profile = await candidate.profile();
      await tokens.write(token.trim(), profile);
      final previousApi = api;
      final changed = account?.id != profile.id;
      if (changed) {
        ++_selection;
        listId = 'favorites';
        listTitle = 'Любимое';
      }
      await store.put('_app', 'account', profile.toJson());
      account = profile;
      api = candidate;
      if (changed) {
        tracks = [];
        ratings = {};
        playlists = [];
        savedCatalogItems = [];
        savedCatalogKnown = false;
        ++_savedRequest;
      }
      await music.configure(profile.id, candidate);
      previousApi?.close();
      await _loadCache();
      connecting = false;
      notifyListeners();
      await refresh();
    } catch (e) {
      if (api != candidate) candidate.close();
      message = e is ZvukException
          ? e.message
          : 'Не удалось сохранить подключение. Попробуй снова.';
      rethrow;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (busy || serverBusy || api == null || account == null) return;
    unawaited(refreshSavedCatalog());
    final id = account!.id, selected = listId;
    final requestApi = api!;
    final revision = _catalogRevision;
    final selection = _selection;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final favorites = await requestApi.favorites();
      final lists = await requestApi.playlists();
      final active = selected == 'favorites'
          ? favorites
          : await requestApi.playlistTracks(selected);
      if (revision != _catalogRevision || account?.id != id) return;
      await store.saveTracks(id, 'favorites', favorites);
      await store.put(id, 'playlists', lists.map((p) => p.toJson()).toList());
      if (selected != 'favorites') await store.saveTracks(id, selected, active);
      if (account?.id == id) {
        if (revision != _catalogRevision) return;
        favoriteTracks = favorites;
        playlists = lists;
        if (selection == _selection) tracks = active;
      }
    } catch (e) {
      if (account?.id == id) {
        message = e is ZvukException
            ? e.message
            : 'Обновление не удалось. Сохранённая библиотека доступна.';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selectPlaylist(PlaylistInfo? playlist) async {
    final id = account!.id;
    final selection = ++_selection;
    listId = playlist?.id ?? 'favorites';
    listTitle = playlist?.title ?? 'Любимое';
    final selected = listId;
    final cached = await store.loadTracks(id, selected);
    final order = await store.loadOrder(id, selected);
    if (selection != _selection || account?.id != id) return;
    tracks = cached;
    manualOrder = order;
    notifyListeners();
    if (api == null) return;
    try {
      final result = selected == 'favorites'
          ? await api!.favorites()
          : await api!.playlistTracks(selected);
      await store.saveTracks(id, selected, result);
      if (selection == _selection && account?.id == id) {
        tracks = result;
        if (selected == 'favorites') favoriteTracks = result;
        message = null;
      }
    } catch (e) {
      if (selection == _selection) {
        message = e is ZvukException
            ? e.message
            : 'Не удалось загрузить плейлист.';
      }
    }
    notifyListeners();
  }

  Future<void> openLibrary(PlaylistInfo p) async {
    await selectPlaylist(p);
    libraryRequests++;
    notifyListeners();
  }

  Future<void> setSort(bool value) async {
    ranked = value;
    if (!ranked) unrated = false;
    notifyListeners();
    if (account == null) return;
    try {
      await store.put(account!.id, 'sort', value ? 'rating' : 'manual');
    } catch (_) {
      message = 'Режим сортировки не сохранился. Попробуй снова.';
      notifyListeners();
    }
  }

  void setUnrated(bool value) {
    unrated = value;
    notifyListeners();
  }

  Future<String> vote(Track track, int delta) async {
    final id = account!.id;
    final event = await store.vote(id, track, delta);
    final updated = await store.ratings(id);
    if (account?.id == id) {
      ratings = updated;
      music.setNotificationRatings(id, ratings);
      // Keep the song visible after its first vote rather than hiding it in
      // the unrated-only view. Votes never alter library membership or queue.
      unrated = false;
      notifyListeners();
    }
    return event;
  }

  Future<void> undo(String accountId, String event) async {
    await store.undo(accountId, event);
    if (account?.id == accountId) {
      ratings = await store.ratings(accountId);
      music.setNotificationRatings(accountId, ratings);
      notifyListeners();
    }
  }

  Future<int> importRatings(String source) async {
    final id = account!.id;
    final added = await store.importRatings(id, source);
    if (account?.id == id) {
      ratings = await store.ratings(id);
      music.setNotificationRatings(id, ratings);
      final selected = listId;
      final order = await store.loadOrder(id, selected);
      if (account?.id == id && listId == selected) manualOrder = order;
      notifyListeners();
    }
    return added;
  }

  Future<T> _edit<T>(Future<T> Function(ZvukApi api, String accountId) action) {
    final session = api, id = account?.id;
    final result = _edits.catchError((_) {}).then((_) async {
      if (session == null ||
          id == null ||
          api != session ||
          account?.id != id) {
        throw const ZvukException('Подключение изменилось. Повтори действие.');
      }
      _catalogRevision++;
      serverBusy = true;
      notifyListeners();
      try {
        return await action(session, id);
      } finally {
        _catalogRevision++;
        serverBusy = false;
        notifyListeners();
      }
    });
    _edits = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _readBack(ZvukApi session, Future<void> Function() read) async {
    try {
      await read();
    } catch (_) {
      if (api == session) message = 'Изменение сохранено в Звуке. Обнови библиотеку, когда появится интернет.';
    }
  }

  Future<void> _listsAfterEdit(ZvukApi session, String id) async {
    final lists = await session.playlists();
    await store.put(id, 'playlists', lists.map((p) => p.toJson()).toList());
    if (api == session && account?.id == id) {
      playlists = lists;
      notifyListeners();
    }
  }

  Future<void> _tracksAfterEdit(
    ZvukApi session,
    String id,
    String playlistId,
  ) async {
    final fresh = await session.playlistTracks(playlistId);
    await store.saveTracks(id, playlistId, fresh);
    if (api == session && account?.id == id && listId == playlistId) {
      tracks = fresh;
    }
    await _readBack(session, () => _listsAfterEdit(session, id));
  }

  Future<PlaylistInfo> _owned(ZvukApi session, String id) async {
    final lists = await session.getPlaylists([id]);
    if (lists.isEmpty || !owns(lists.single)) {
      throw const ZvukException('Изменять можно только свои плейлисты.');
    }
    return lists.single;
  }

  Future<void> setFavorite(Track track, bool liked) => _edit((
    session,
    id,
  ) async {
    await session.setCollectionItem(track.id, liked: liked);
    if (api == session && account?.id == id) {
      favoriteTracks = favoriteTracks.where((t) => t.id != track.id).toList();
      if (liked) favoriteTracks.insert(0, track);
      if (listId == 'favorites') tracks = favoriteTracks;
    }
    await _readBack(session, () async {
      final favorites = await session.favorites();
      await store.saveTracks(id, 'favorites', favorites);
      if (api == session && account?.id == id) {
        favoriteTracks = favorites;
        if (listId == 'favorites') tracks = favorites;
      }
    });
  });

  Future<void> savePlaylist(PlaylistInfo p, bool liked) =>
      _edit((session, id) async {
        await session.setCollectionItem(p.id, liked: liked, playlist: true);
        if (api == session) {
          playlists = playlists.where((item) => item.id != p.id).toList();
          if (liked) playlists.add(p);
          if (!liked && listId == p.id) await selectPlaylist(null);
        }
        await _readBack(session, () => _listsAfterEdit(session, id));
      });

  Future<PlaylistInfo> createPlaylist(
    String name, {
    List<String> trackIds = const [],
  }) => _edit((session, id) async {
    final created = await session.createPlaylist(
      name.trim(),
      trackIds: trackIds,
    );
    // Creation succeeds before collection refresh: avoid repeating a successful
    // create merely because the metadata request was interrupted.
    final p = PlaylistInfo(
      created,
      name.trim(),
      ownerId: id,
      trackCount: trackIds.length,
    );
    if (api == session && account?.id == id) playlists = [...playlists, p];
    try {
      await _readBack(session, () => _listsAfterEdit(session, id));
    } catch (_) {
      /* Refresh can be retried. */
    }
    return p;
  });

  Future<void> renamePlaylist(PlaylistInfo p, String name) =>
      _edit((session, id) async {
        await _owned(session, p.id);
        await session.renamePlaylist(p.id, name.trim());
        if (api == session && listId == p.id) listTitle = name.trim();
        await _readBack(session, () => _listsAfterEdit(session, id));
      });

  Future<void> deletePlaylist(PlaylistInfo p) => _edit((session, id) async {
    await _owned(session, p.id);
    await session.deletePlaylist(p.id);
    if (api == session) {
      playlists = playlists.where((item) => item.id != p.id).toList();
      if (listId == p.id) await selectPlaylist(null);
    }
    await _readBack(session, () => _listsAfterEdit(session, id));
  });

  Future<void> addToPlaylist(PlaylistInfo p, Track track) =>
      _edit((session, id) async {
        await _owned(session, p.id);
        await session.addPlaylistTracks(p.id, [track.id]);
        await _readBack(session, () => _tracksAfterEdit(session, id, p.id));
      });

  Future<void> removeFromPlaylist(
    PlaylistInfo p,
    List<Track> snapshot,
    int index,
  ) => _edit((session, id) async {
    final fresh = await session.playlistTracks(p.id);
    if (!listEquals(
      fresh.map((t) => t.id).toList(),
      snapshot.map((t) => t.id).toList(),
    )) {
      throw const ZvukException(
        'Плейлист изменился. Обнови его перед удалением песни.',
      );
    }
    final metadata = await _owned(session, p.id);
    fresh.removeAt(index);
    await session.replacePlaylistTracks(
      metadata,
      fresh.map((t) => t.id).toList(),
    );
    await _readBack(session, () => _tracksAfterEdit(session, id, p.id));
  });
}
