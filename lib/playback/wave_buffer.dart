import '../data/models.dart';

/// Shares one fetch and invalidates its result when the listening mode changes.
class WaveBuffer {
  int _generation = 0;
  Future<List<Track>>? _pending;
  void cancel() {
    _generation++;
    _pending = null;
  }

  Future<List<Track>> load(
    Future<List<Track>> Function() fetch,
    Set<String> recentIds,
  ) {
    if (_pending != null) return _pending!;
    final generation = _generation;
    final seen = {...recentIds};
    late final Future<List<Track>> request;
    request =
        (() async {
          // A repeated recommendation batch must not leave an endless retry loop.
          for (var attempt = 0; attempt < 2; attempt++) {
            final tracks = await fetch();
            if (generation != _generation) return <Track>[];
            final fresh = tracks.where((t) => seen.add(t.id)).toList();
            if (fresh.isNotEmpty || tracks.isEmpty) return fresh;
          }
          return <Track>[];
        })().whenComplete(() {
          if (identical(_pending, request)) _pending = null;
        });
    _pending = request;
    return request;
  }
}
