part of 'music_handler.dart';

extension QueueControls on MusicHandler {
  Future<int> appendSimilar(Track track, {bool Function()? cancelled}) async {
    final api = _api, account = _account, version = playlist.version;
    if (api == null) {
      throw const ZvukException('Обнови подключение в настройках.');
    }
    final result = await api.recommendations(WaveSource.fromTrack(track));
    if (cancelled?.call() == true) return 0;
    if (api != _api || account != _account || version != playlist.version) {
      throw const ZvukException(
        'Очередь изменилась. Добавь похожие песни ещё раз.',
      );
    }
    final seen = {track.id, ...playlist.tracks.map((t) => t.id)};
    final fresh = result.tracks.where((t) => seen.add(t.id)).take(15).toList();
    for (final song in fresh) {
      playlist.enqueue(song);
    }
    if (fresh.isNotEmpty) {
      _publishQueue();
      _broadcast();
      await _saveSafely();
    }
    return fresh.length;
  }

  Future<bool> playQueueItem(int index, int version) async {
    if (!_validQueueTarget(index, version)) return false;
    await skipToQueueItem(index);
    return true;
  }

  bool _validQueueTarget(int index, int version) =>
      version == playlist.version && index >= 0 && index < playlist.length;

  Future<bool> moveInQueue(int from, int to, int version) async {
    if (!_validQueueTarget(from, version) || !_validQueueTarget(to, version)) {
      return false;
    }
    playlist.move(from, to);
    isShuffled = false;
    _publishQueue();
    _broadcast();
    await _saveSafely();
    return true;
  }

  Future<bool> moveNextInQueue(int at, int version) async {
    if (!_validQueueTarget(at, version) || at == playlist.index) return false;
    // Removing an earlier occurrence shifts the playing index one place left.
    final target = at < playlist.index ? playlist.index : playlist.index + 1;
    return moveInQueue(at, target, version);
  }

  Future<bool> removeFromQueue(int at, int version) async {
    if (!_validQueueTarget(at, version)) return false;
    final wasPlaying = player.playing || _loading;
    final hadNext = playlist.hasNext;
    final removedCurrent = playlist.remove(at);
    if (playlist.current == null) sleepTimer.cancel();
    _publishQueue();
    if (removedCurrent) {
      _restoredPosition = Duration.zero;
      await _loadAndPlay(autoplay: wasPlaying && hadNext);
    } else {
      _broadcast();
      await _saveSafely();
    }
    return true;
  }

  Future<void> shuffleUpcoming() async {
    playlist.shuffleUpcoming();
    isShuffled = true;
    _publishQueue();
    _broadcast();
    await _saveSafely();
  }

  Future<void> clearUpcoming() async {
    final waiting = _waitingNext || _startingWave;
    _cancelWave();
    playlist.clearUpcoming();
    repeatMode = AudioServiceRepeatMode.none;
    if (waiting) await pause();
    _publishQueue();
    _broadcast();
    await _saveSafely();
  }

  void setSleepTimer(Duration duration) {
    sleepTimer.schedule(duration, DateTime.now());
    revision.value++;
  }

  void sleepAfterSong() {
    sleepTimer.afterSong();
    revision.value++;
  }

  void cancelSleepTimer() {
    sleepTimer.cancel();
    revision.value++;
  }
}
