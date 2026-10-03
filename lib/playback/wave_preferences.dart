part of 'music_handler.dart';

extension WavePreferences on MusicHandler {
  Future<void> setWaveOptions(WaveOptions options) async {
    final account = _account;
    if (account == null) {
      throw const ZvukException('Обнови подключение в настройках.');
    }
    final normalized = WaveOptions.fromJson(options.toJson());
    await store.put(account, 'waveOptions', normalized.toJson());
    if (_account != account) return;
    _waveOptions = normalized;
    if (isWave && _waveSource.kind == WaveKind.personal) {
      _waveGeneration++;
      _wave.cancel();
      _fillingWave = null;
      _waveCursor = 0;
      playlist.clearUpcoming();
      error.value = null;
      _publishQueue();
      await _saveSafely();
      _prefetchWave();
    }
    revision.value++;
  }
}
