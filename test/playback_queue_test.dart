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
}
