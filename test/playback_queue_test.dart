import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/playback_queue.dart';

void main() {
  const a = Track(id: 'a', title: 'A'),
      b = Track(id: 'b', title: 'B'),
      c = Track(id: 'c', title: 'C');
  test('Queue snapshots source, inserts next, keeps duplicates and stops', () {
    final source = [a, b];
    final q = PlaybackQueue()..replace(source, 0);
    source.clear();
    q.enqueue(c, next: true);
    q.enqueue(a);
    expect(q.tracks.map((t) => t.id), ['a', 'c', 'b', 'a']);
    expect(q.current, a);
    expect(q.advance(), true);
    expect(q.current, c);
    q.advance();
    q.advance();
    expect(q.advance(), false);
    expect(q.index, 3);
    final restored = PlaybackQueue()..restore(q.toJson());
    expect(restored.current!.id, 'a');
    expect(restored.index, 3);
    expect(() => q.tracks.clear(), throwsUnsupportedError);
  });
  test(
    'Moving across the current occurrence keeps that exact duplicate selected',
    () {
      final q = PlaybackQueue()..replace([a, b, a, c], 2);
      final key = q.entryKey(2), version = q.version;
      q.move(2, 0);
      expect(q.index, 0);
      expect(q.entryKey(q.index), key);
      q.move(3, 0);
      expect(q.index, 1);
      expect(q.entryKey(q.index), key);
      expect(q.version, greaterThan(version));
      q.remove(2);
      expect(q.entryKey(q.index), key);
      expect(q.tracks.map((t) => t.id), ['c', 'a', 'b']);
    },
  );
  test(
    'Removal picks the next slot or previous at the end, then empty is safe',
    () {
      final q = PlaybackQueue()..replace([a, b, c], 1);
      expect(q.remove(1), true);
      expect(q.current, c);
      expect(q.remove(0), false);
      expect(q.current, c);
      q.remove(0);
      expect(q.current, isNull);
      expect(q.index, 0);
      expect(q.advance(), false);
      expect(() => q.remove(0), throwsRangeError);
      q.enqueue(a);
      expect(q.current, a);
    },
  );
  test(
    'Upcoming edits preserve current key and prefix, shuffle keeps duplicates',
    () {
      final q = PlaybackQueue()..replace([a, b, a, c, c], 1);
      final key = q.entryKey(1);
      q.shuffleUpcoming(Random(3));
      expect(q.tracks.take(2), [a, b]);
      expect(q.tracks.skip(2), unorderedEquals([a, c, c]));
      expect(q.entryKey(q.index), key);
      q.clearUpcoming();
      expect(q.tracks, [a, b]);
      expect(q.entryKey(q.index), key);
      final restored = PlaybackQueue()..restore(q.toJson());
      expect(restored.current!.id, 'b');
    },
  );
  test('Index changes invalidate stale queue operations; replacing regenerates keys', () {
    final q = PlaybackQueue()..replace([a, b], 0);
    var version = q.version;
    q.advance();
    expect(q.version, greaterThan(version));
    version = q.version;
    q.previous();
    expect(q.version, greaterThan(version));
    final key = q.entryKey(0);
    q.replace([a, b], 0);
    expect(q.entryKey(0), isNot(key));
    expect(() => q.move(0, 2), throwsRangeError);
    expect(q.tracks, [a, b]);
  });
}
