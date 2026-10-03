import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/catalog_models.dart';
import 'data/search_history_store.dart';
import 'data/search_models.dart';
import 'data/zvuk_api.dart';

class MusicSearchController extends ChangeNotifier {
  MusicSearchController(
    this.api,
    this.history,
    this.account, {
    this.debounce = const Duration(milliseconds: 350),
  });
  final ZvukApi? api;
  final SearchHistoryStore history;
  final String account;
  final Duration debounce;
  CatalogKind? kind;
  String query = '', error = '', historyError = '';
  List<SearchHit> hits = [];
  List<String> recent = [];
  String? next;
  bool busy = false, searched = false;
  bool _disposed = false, _failedMore = false;
  int _request = 0, _historyRequest = 0;
  Timer? _timer;

  Future<void> initialize() => _historyAction(() async {});

  Future<void> _historyAction(Future<void> Function() action) async {
    final generation = ++_historyRequest;
    try {
      await action();
      final values = await history.recent(account);
      if (_disposed || generation != _historyRequest) return;
      recent = values;
      historyError = '';
    } catch (_) {
      if (_disposed || generation != _historyRequest) return;
      historyError = 'Не удалось обновить историю поиска.';
    }
    notifyListeners();
  }

  Future<void> remember() =>
      _historyAction(() => history.record(account, query));
  Future<void> removeRecent(String value) =>
      _historyAction(() => history.remove(account, value));
  Future<void> clearRecent() => _historyAction(() => history.clear(account));

  void _reset() {
    _timer?.cancel();
    ++_request;
    hits = [];
    next = null;
    busy = false;
    searched = false;
    error = '';
    _failedMore = false;
  }

  void edit(String value) {
    final normalized = normalizeSearch(value);
    if (query == normalized) return;
    _reset();
    query = normalized;
    if (query.runes.length >= 2) {
      busy = true;
      _timer = Timer(debounce, () => _search());
    }
    notifyListeners();
  }

  Future<void> choose(CatalogKind? value) async {
    if (kind == value) return;
    _reset();
    kind = value;
    notifyListeners();
    if (query.isNotEmpty) await _search();
  }

  Future<void> submit(String value) async {
    edit(value);
    _timer?.cancel();
    if (query.isEmpty) return;
    unawaited(remember());
    await _search();
  }

  Future<void> retry() => _search(more: _failedMore);
  Future<void> loadMore() async {
    if (!busy && next != null) await _search(more: true);
  }

  Future<void> _search({bool more = false}) async {
    _timer?.cancel();
    if (_disposed || query.isEmpty) return;
    final generation = ++_request, cursor = more ? next : null;
    final selected = kind;
    busy = true;
    error = '';
    _failedMore = more;
    if (!more) {
      hits = [];
      next = null;
      searched = false;
    }
    notifyListeners();
    try {
      if (api == null) {
        throw const ZvukException('Обнови подключение в настройках.');
      }
      final List<SearchHit> result;
      String? newCursor;
      if (selected == null) {
        result = await api!.quickSearch(query);
      } else {
        final page = await api!.searchCatalog(query, selected, cursor: cursor);
        result = [
          ...page.tracks.map(SearchHit.track),
          ...page.items.map(SearchHit.item),
        ];
        newCursor = page.next;
      }
      if (_disposed || generation != _request) return;
      final seen = <String>{};
      hits = [
        ...(more ? hits : <SearchHit>[]),
        ...result,
      ].where((h) => seen.add(h.key)).toList();
      next = newCursor == cursor ? null : newCursor;
      searched = true;
    } catch (e) {
      if (_disposed || generation != _request) return;
      error = e is ZvukException
          ? e.message
          : 'Не удалось найти музыку. Попробуй ещё раз.';
    } finally {
      if (!_disposed && generation == _request) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    ++_request;
    super.dispose();
  }
}
