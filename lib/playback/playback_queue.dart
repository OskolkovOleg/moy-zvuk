import '../data/models.dart';

class PlaybackQueue {
  List<Track> _tracks = [];
  int index = 0;
  List<Track> get tracks => List.unmodifiable(_tracks);
  Track? get current => _tracks.isEmpty ? null : _tracks[index];
  bool get hasNext => index + 1 < _tracks.length;
  void replace(List<Track> tracks, int start) {
    if (tracks.isNotEmpty && (start < 0 || start >= tracks.length)) {
      throw RangeError.index(start, tracks);
    }
    _tracks = List.of(tracks);
    index = tracks.isEmpty ? 0 : start;
  }

  void enqueue(Track track, {bool next = false}) {
    if (next && _tracks.isNotEmpty) {
      _tracks.insert(index + 1, track);
    } else {
      _tracks.add(track);
    }
  }

  bool advance() {
    if (!hasNext) return false;
    index++;
    return true;
  }

  bool previous() {
    if (index == 0) return false;
    index--;
    return true;
  }

  void jump(int target) {
    if (target < 0 || target >= _tracks.length) {
      throw RangeError.index(target, _tracks);
    }
    index = target;
  }

  Map<String, dynamic> toJson() => {
    'tracks': _tracks.map((t) => t.toJson()).toList(),
    'index': index,
  };
  void restore(Map<String, dynamic> json) {
    final tracks = (json['tracks'] as List)
        .map((j) => Track.fromJson(j))
        .toList();
    replace(
      tracks,
      (json['index'] as int).clamp(0, tracks.isEmpty ? 0 : tracks.length - 1),
    );
  }
}
