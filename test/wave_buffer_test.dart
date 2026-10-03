import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/wave_buffer.dart';

void main() {
  const old = Track(id: 'old', title: 'Old'),
      fresh = Track(id: 'new', title: 'New');
  test(
    'Deduplicates recent and repeated items, shares the pending fetch',
    () async {
      final buffer = WaveBuffer(), result = Completer<List<Track>>();
      var calls = 0;
      Future<List<Track>> fetch() {
        calls++;
        return result.future;
      }

      final a = buffer.load(fetch, {'old'}), b = buffer.load(fetch, {'old'});
      expect(identical(a, b), true);
      result.complete([old, fresh, fresh]);
      expect((await a).map((t) => t.id), ['new']);
      expect(calls, 1);
    },
  );
  test(
    'Cancellation rejects late result without clearing a newer request',
    () async {
      final buffer = WaveBuffer(),
          first = Completer<List<Track>>(),
          second = Completer<List<Track>>();
      final a = buffer.load(() => first.future, {});
      buffer.cancel();
      final b = buffer.load(() => second.future, {});
      first.complete([old]);
      expect(await a, isEmpty);
      expect(identical(b, buffer.load(() async => [], {})), true);
      second.complete([fresh]);
      expect(await b, [fresh]);
    },
  );
  test(
    'Failure can retry; empty or repeated results have bounded requests',
    () async {
      final buffer = WaveBuffer();
      await expectLater(
        buffer.load(() async => throw StateError('offline'), {}),
        throwsStateError,
      );
      expect(await buffer.load(() async => [fresh], {}), [fresh]);
      var calls = 0;
      expect(
        await buffer.load(() async {
          calls++;
          return [old];
        }, {'old'}),
        isEmpty,
      );
      expect(calls, 2);
      expect(await buffer.load(() async => [], {}), isEmpty);
    },
  );
}
