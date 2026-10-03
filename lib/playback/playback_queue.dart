import 'dart:math';

import '../data/models.dart';

class PlaybackQueue {
  List<Track> _tracks = [];
  int index = 0, version = 0, _nextKey = 0;
  List<int> _keys = [];
  int entryKey(int at) => _keys[at];
  int get length => _tracks.length;
  List<Track> get tracks => List.unmodifiable(_tracks);
  Track? get current => _tracks.isEmpty ? null : _tracks[index];
  bool get hasNext => index + 1 < _tracks.length;
  void replace(List<Track> tracks, int start) {
    if (tracks.isNotEmpty && (start < 0 || start >= tracks.length)) {
      throw RangeError.index(start, tracks);
    }
    _tracks = List.of(tracks);
    _keys = List.generate(tracks.length, (_) => _nextKey++);
    version++;
    index = tracks.isEmpty ? 0 : start;
  }

  void enqueue(Track track, {bool next = false}) {
    if (next && _tracks.isNotEmpty) {
      _tracks.insert(index + 1, track);
      _keys.insert(index + 1, _nextKey++);
    } else {
      _tracks.add(track);
      _keys.add(_nextKey++);
    }
    version++;
  }

  bool advance() {
    if (!hasNext) return false;
    index++;
    version++;
    return true;
  }

  bool previous() {
    if (index == 0) return false;
    index--;
    version++;
    return true;
  }

  void jump(int target) {
    if (target < 0 || target >= _tracks.length) {
      throw RangeError.index(target, _tracks);
    }
    index = target;
    version++;
  }

  void move(int from, int to) {
    RangeError.checkValidIndex(from, _tracks);
    RangeError.checkValidIndex(to, _tracks);
    if (from == to) return;
    final currentKey = _keys[index];
    final track = _tracks.removeAt(from), key = _keys.removeAt(from);
    _tracks.insert(to, track);
    _keys.insert(to, key);
    index = _keys.indexOf(currentKey);
    version++;
  }

  bool remove(int at) {
    RangeError.checkValidIndex(at, _tracks);
    final currentRemoved = at == index;
    _tracks.removeAt(at);
    _keys.removeAt(at);
    if (at < index || index >= _tracks.length) index--;
    if (_tracks.isEmpty) index = 0;
    version++;
    return currentRemoved;
  }

  void clearUpcoming() {
    if (!hasNext) return;
    _tracks.removeRange(index + 1, _tracks.length);
    _keys.removeRange(index + 1, _keys.length);
    version++;
  }

  void shuffleUpcoming([Random? random]) {
    if (index + 2 >= _tracks.length) return;
    final items = [
      for (var i = index + 1; i < _tracks.length; i++) (_tracks[i], _keys[i]),
    ]..shuffle(random);
    for (var i = 0; i < items.length; i++) {
      _tracks[index + 1 + i] = items[i].$1;
      _keys[index + 1 + i] = items[i].$2;
    }
    version++;
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
