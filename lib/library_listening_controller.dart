part of 'app_controller.dart';

extension LibraryListening on AppController {
  LibrarySort get librarySort {
    if (_sortAccount != account?.id || _sortList != listId) {
      _sortAccount = account?.id;
      _sortList = listId;
      _librarySort = LibrarySort.scores;
      _listeningStats = null;
      _lastHistoryRemote = null;
      libraryHistoryError = null;
      libraryHistoryLoading = false;
      ++_historyRequest;
    }
    return _librarySort;
  }

  ListeningStats? get listeningStats {
    librarySort;
    return _listeningStats;
  }

  Future<void> setLibrarySort(LibrarySort sort) async {
    librarySort;
    final request = ++_sortRequest;
    if (sort == LibrarySort.newest) {
      final id = account?.id, selected = listId, selection = _selection;
      if (id == null || selected != 'favorites') return;
      bool current() =>
          !_disposed &&
          request == _sortRequest &&
          account?.id == id &&
          listId == selected &&
          _selection == selection;
      try {
        var known = await store.hasFavoriteAdditionOrder(id);
        if (!current()) return;
        if (!known) {
          await refresh();
          if (!current()) return;
          known = await store.hasFavoriteAdditionOrder(id);
          if (!current()) return;
        }
        if (!known) {
          message = busy || serverBusy
              ? 'Библиотека ещё обновляется. Повтори выбор после обновления.'
              : 'Обнови библиотеку при подключении к интернету, чтобы получить порядок добавления.';
          notifyListeners();
          return;
        }
      } catch (_) {
        if (current()) {
          message = 'Не удалось прочитать порядок добавления. Попробуй обновить библиотеку.';
          notifyListeners();
        }
        return;
      }
      message = null;
    }
    if (_disposed) return;
    _librarySort = sort;
    ++_historyRequest;
    libraryHistoryLoading = false;
    libraryHistoryError = null;
    resortLibrary(reloadHistory: false);
    if (sort.needsListeningStats) {
      await refreshLibraryListening(remote: sort == LibrarySort.oldest);
    }
  }

  Future<void> refreshLibraryListening({bool remote = false}) async {
    final sort = librarySort, id = account?.id, selected = listId;
    if (id == null || !sort.needsListeningStats) return;
    final request = ++_historyRequest,
        revision = _ratingRevision,
        session = api;
    bool current() =>
        !_disposed &&
        account?.id == id &&
        listId == selected &&
        request == _historyRequest &&
        _librarySort == sort;
    libraryHistoryLoading = true;
    libraryHistoryError = null;
    notifyListeners();
    try {
      final statsStore = historyStatsStore;
      var stats = await statsStore.load(id);
      if (!current()) return;
      _listeningStats = stats;
      if (remote && session != null) {
        try {
          final entries = <ListeningEntry>[];
          int? offset = 0;
          for (var page = 0; page < 4 && offset != null; page++) {
            final result = await session.listeningHistory(
              offset: offset,
              limit: 250,
            );
            if (!current() || api != session) return;
            entries.addAll(result.entries);
            offset = result.nextOffset;
          }
          await statsStore.mergeDates(id, entries);
          stats = await statsStore.load(id);
          if (current()) _lastHistoryRemote = DateTime.now();
        } catch (_) {
          if (current()) {
            libraryHistoryError =
                'История Звука недоступна. Используем сохранённые даты.';
          }
        }
      }
      if (!current()) return;
      _listeningStats = stats;
      // Votes must never make a row jump as an asynchronous history read ends.
      if (revision == _ratingRevision) resortLibrary(reloadHistory: false);
    } catch (_) {
      if (current()) {
        libraryHistoryError =
            'Не удалось прочитать статистику. Попробуй обновить список.';
      }
    } finally {
      if (current()) {
        libraryHistoryLoading = false;
        notifyListeners();
      }
    }
  }
}
