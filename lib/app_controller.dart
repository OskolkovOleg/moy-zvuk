import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/library_store.dart';
import 'data/models.dart';
import 'data/token_store.dart';
import 'data/zvuk_api.dart';
import 'playback/music_handler.dart';
import 'playback/shuffle_tracks.dart';

class AppController extends ChangeNotifier {
  AppController(this.store, this.music, {this.tokens = const TokenStore()});
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
  int _selection = 0;

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
    tracks = await store.loadTracks(id, listId);
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
    if (busy || api == null || account == null) return;
    final id = account!.id, selected = listId;
    final requestApi = api!;
    final selection = _selection;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final favorites = await requestApi.favorites();
      final lists = await requestApi.playlists();
      await store.saveTracks(id, 'favorites', favorites);
      await store.put(id, 'playlists', lists.map((p) => p.toJson()).toList());
      final active = selected == 'favorites'
          ? favorites
          : await requestApi.playlistTracks(selected);
      if (selected != 'favorites') await store.saveTracks(id, selected, active);
      if (account?.id == id) {
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
    if (account?.id == id) {
      ratings = await store.ratings(id);
      notifyListeners();
    }
    return event;
  }

  Future<void> undo(String accountId, String event) async {
    await store.undo(accountId, event);
    if (account?.id == accountId) {
      ratings = await store.ratings(accountId);
      notifyListeners();
    }
  }

  Future<int> importRatings(String source) async {
    final id = account!.id;
    final added = await store.importRatings(id, source);
    if (account?.id == id) {
      ratings = await store.ratings(id);
      final selected = listId;
      final order = await store.loadOrder(id, selected);
      if (account?.id == id && listId == selected) manualOrder = order;
      notifyListeners();
    }
    return added;
  }
}
