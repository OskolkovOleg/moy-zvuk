import 'dart:collection';

import 'models.dart';

/// Keeps rows in place while scores change during a library visit.
class LibraryDisplayOrder {
  String? _account, _list;
  List<String>? _ids;

  void reset() => _ids = null;

  List<Track> arrange(
    String? account,
    String list,
    List<Track> tracks,
    Map<String, Rating> ratings,
  ) {
    if (_account != account || _list != list) reset();
    _account = account;
    _list = list;
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
      rankedTracks([
        for (var i = 0; i < tracks.length; i++)
          if (!used.contains(i)) tracks[i],
      ], ratings),
    );
    _ids = visible.map((t) => t.id).toList();
    return List.unmodifiable(visible);
  }
}
