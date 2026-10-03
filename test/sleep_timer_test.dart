import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/playback/sleep_timer.dart';

void main() {
  final now = DateTime.utc(2026, 10, 3);
  test('Deadline expires once at exact boundary and counts wall time', () {
    final timer = SleepTimerState()..schedule(const Duration(minutes: 15), now);
    expect(
      timer.remaining(now.add(const Duration(minutes: 5))),
      const Duration(minutes: 10),
    );
    expect(timer.expire(now.add(const Duration(minutes: 14))), false);
    expect(timer.expire(now.add(const Duration(minutes: 15))), true);
    expect(timer.active, false);
    expect(timer.expire(now.add(const Duration(minutes: 16))), false);
  });
  test('After song, timed mode and cancellation replace each other', () {
    final timer = SleepTimerState()..afterSong();
    expect(timer.expire(now), false);
    expect(timer.finishSong(), true);
    expect(timer.finishSong(), false);
    timer.afterSong();
    timer.schedule(const Duration(seconds: 3), now);
    expect(timer.finishSong(), false);
    timer.cancel();
    expect(timer.active, false);
    expect(timer.remaining(now), isNull);
    expect(() => timer.schedule(Duration.zero, now), throwsArgumentError);
  });
}
