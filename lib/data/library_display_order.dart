import 'dart:collection';

import 'models.dart';
import 'library_filter.dart';
import 'listening_stats.dart';

/// Keeps rows in place while scores change during a library visit.
class LibraryDisplayOrder {
  String? _account, _list;
  List<String>? _ids;
  LibraryFilter? _filter;
  LibrarySort? _sort;
  final _eligible = <String, bool>{};

  void reset() {
    _ids = null;
    _eligible.clear();
  }

  List<Track> arrange(
    String? account,
    String list,
    List<Track> tracks,
    Map<String, Rating> ratings, {
    LibraryFilter filter = LibraryFilter.all,
    LibrarySort sort = LibrarySort.scores,
    ListeningStats? stats,
    DateTime? now,
  }) {
    if (_account != account ||
        _list != list ||
        _filter != filter ||
        _sort != sort) {
      reset();
    }
    _account = account;
    _list = list;
    _filter = filter;
    _sort = sort;
    if (filter.isActive) {
      final present = tracks.map((t) => t.id).toSet();
      _eligible.removeWhere((id, _) => !present.contains(id));
      tracks = [
        for (final track in tracks)
          if (_eligible.putIfAbsent(
            track.id,
            () => filter.matches(track, ratings),
          ))
            track,
      ];
    }
    final previous = _ids;
    final visible = <Track>[];
    final used = <int>{};
    if (previous != null) {
      final available = <String, Queue<int>>{};
      for (var i = 0; i < tracks.length; i++) {
        available.putIfAbsent(tracks[i].id, Queue<int>.new).add(i);
      }
      for (final id in previous) {
        final matches = available[id];
        if (matches == null || matches.isEmpty) continue;
        final index = matches.removeFirst();
        used.add(index);
        visible.add(tracks[index]);
      }
    }
    visible.addAll(
      sortedLibraryTracks(
        [
          for (var i = 0; i < tracks.length; i++)
            if (!used.contains(i)) tracks[i],
        ],
        ratings,
        sort: sort,
        stats: stats,
        now: now,
      ),
    );
    _ids = visible.map((t) => t.id).toList();
    return List.unmodifiable(visible);
  }
}
