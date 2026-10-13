part of 'music_handler.dart';

extension StreamRecovery on MusicHandler {
  bool get _networkBlocked =>
      _networkBlockedUntil?.isAfter(DateTime.now()) == true;

  void _playbackFailed(Object failure) {
    // setUrl failures belong to the loading task; late failures belong to the
    // playing occurrence. A pause or a new selection revokes playback intent.
    if (!_playIntent || !_loaded || _loading || playlist.current == null) {
      return;
    }
    final key = playlist.entryKey(playlist.index);
    final retry = _runtimeRetries.add(key);
    if (!retry) _failedRuntimeEntries.add(key);
    _restoredPosition = retry ? position : Duration.zero;
    unawaited(_loadAndPlay(forceNetwork: false, skipCurrent: !retry));
  }

  bool _advanceAfterFailure(Set<int> visited) {
    if (playlist.current == null) return false;
    var next = playlist.index + 1;
    if (next >= playlist.length) {
      if (repeatMode != AudioServiceRepeatMode.all || isWave) return false;
      next = 0;
    }
    if (visited.contains(playlist.entryKey(next))) return false;
    playlist.jump(next);
    _restoredPosition = Duration.zero;
    _historyRecorded = false;
    _publishQueue(updateQueue: false);
    return true;
  }

  Future<void> _prepareRemote(
    ZvukApi api,
    Track track,
    Duration position,
    int generation,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      // Obtain a new signed URL on every attempt; never reuse an expired URL.
      final url = await api.streamUrl(
        track.id,
        quality: _audioPreferences.streaming,
      );
      if (generation != _generation) return;
      try {
        await player
            .setUrl(url, initialPosition: position)
            .timeout(const Duration(seconds: 15));
        return;
      } catch (_) {
        if (generation != _generation) return;
        await player.stop();
        if (attempt == 1) rethrow;
      }
    }
  }

  Future<void> _loadAndPlay({
    bool autoplay = true,
    bool forceNetwork = true,
    bool skipCurrent = false,
  }) {
    final generation = ++_generation;
    final api = _api, account = _account;
    if (forceNetwork) {
      _networkBlockedUntil = null;
      _runtimeRetries.clear();
      _failedRuntimeEntries.clear();
    }
    _playIntent = autoplay && playlist.current != null;
    _loaded = false;
    _historyRecorded = false;
    _loading = _playIntent;
    error.value = null;
    unawaited(player.pause());
    unawaited(_saveSafely());
    _broadcast();
    _pending = _pending.catchError((_) {}).then((_) async {
      if (generation != _generation) return;
      if (playlist.current == null || !autoplay) {
        await player.stop();
        if (generation == _generation) {
          _broadcast();
          await _saveSafely();
        }
        return;
      }
      final visited = <int>{};
      final limit = playlist.length;
      String? firstFailure;
      var remoteFailures = 0;
      if (skipCurrent) {
        visited.add(playlist.entryKey(playlist.index));
        if (!_advanceAfterFailure(visited)) {
          await _stopFailed(
            generation,
            'Поток прервался. Доступных песен в очереди больше нет.',
          );
          return;
        }
      }
      for (
        var checked = 0;
        checked < limit && playlist.current != null;
        checked++
      ) {
        if (generation != _generation || !_playIntent) return;
        final track = playlist.current!,
            key = playlist.entryKey(playlist.index);
        if (!visited.add(key)) break;
        var requestedRemote = false;
        try {
          if (_failedRuntimeEntries.contains(key)) {
            throw const ZvukException('Не удалось воспроизвести песню.');
          }
          final position = _restoredPosition;
          final local = account == null
              ? null
              : await downloads.localPath(account, track.id);
          if (generation != _generation) return;
          var prepared = false;
          if (local != null) {
            try {
              await player
                  .setFilePath(local, initialPosition: position)
                  .timeout(const Duration(seconds: 15));
              prepared = true;
            } catch (_) {
              if (generation != _generation) return;
              await player.stop();
            }
          }
          if (generation != _generation) return;
          if (!prepared) {
            if (api == null || _networkBlocked) {
              throw const ZvukException(
                'Соединение недоступно, а эта песня не скачана.',
              );
            }
            requestedRemote = true;
            await _prepareRemote(api, track, position, generation);
          }
          if (generation != _generation || !_playIntent) return;
          _loaded = true;
          _loading = false;
          _restoredPosition = Duration.zero;
          _sourceStartPosition = position;
          error.value = null;
          _broadcast();
          await _saveSafely();
          if (generation != _generation || !_playIntent) return;
          unawaited(
            player.play().catchError((Object failure) {
              if (generation == _generation) _playbackFailed(failure);
            }),
          );
          _prefetchWave();
          return;
        } catch (failure) {
          if (generation != _generation || !_playIntent) return;
          firstFailure ??= failure is ZvukException
              ? failure.message
              : 'Трек не загрузился. Проверь соединение.';
          if (failure is ZvukException && (failure.auth || failure.retryable)) {
            _networkBlockedUntil = DateTime.now().add(
              const Duration(seconds: 30),
            );
          } else if (requestedRemote &&
              failure is! ZvukException &&
              ++remoteFailures >= 2) {
            _networkBlockedUntil = DateTime.now().add(
              const Duration(seconds: 30),
            );
          }
          await player.stop();
          if (generation != _generation || !_playIntent) return;
          if (!_advanceAfterFailure(visited)) break;
        }
      }
      await _stopFailed(
        generation,
        firstFailure ?? 'В очереди нет доступных песен. Проверь соединение или скачай музыку.',
      );
    });
    _prefetchWave();
    return _pending;
  }

  Future<void> _stopFailed(int generation, String message) async {
    if (generation != _generation) return;
    _playIntent = false;
    _loading = false;
    _loaded = false;
    error.value = message;
    await player.stop();
    if (generation != _generation) return;
    _broadcast();
    await _saveSafely();
  }
}
