/// Wall-clock deadline. It keeps counting during pause and is never persisted.
class SleepTimerState {
  DateTime? deadline;
  bool stopsAfterSong = false;
  bool get active => deadline != null || stopsAfterSong;
  void schedule(Duration duration, DateTime now) {
    if (duration <= Duration.zero) throw ArgumentError.value(duration);
    deadline = now.add(duration);
    stopsAfterSong = false;
  }

  void afterSong() {
    deadline = null;
    stopsAfterSong = true;
  }

  void cancel() {
    deadline = null;
    stopsAfterSong = false;
  }

  Duration? remaining(DateTime now) {
    final end = deadline;
    if (end == null) return null;
    final left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool expire(DateTime now) {
    if (deadline == null || now.isBefore(deadline!)) return false;
    cancel();
    return true;
  }

  bool finishSong() {
    if (!stopsAfterSong) return false;
    cancel();
    return true;
  }
}
