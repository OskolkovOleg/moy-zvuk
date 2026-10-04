import 'dart:async';

import 'package:audio_service/audio_service.dart' hide Rating;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/library_store.dart';
import '../data/audio_preferences.dart';
import '../data/history_store.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import '../data/wave_source.dart';
import '../data/wave_options.dart';
import '../downloads/download_manager.dart';
import 'playback_queue.dart';
import 'wave_buffer.dart';
import 'sleep_timer.dart';

part 'queue_controls.dart';
part 'notification_controls.dart';
part 'wave_preferences.dart';

class MusicHandler extends BaseAudioHandler with SeekHandler {
  MusicHandler(this.store) : downloads = DownloadManager(store) {
    player.playbackEventStream.listen(
      (_) => _broadcast(),
      onError: (Object _, StackTrace _) {
        error.value =
            'Не удалось воспроизвести трек. Повтори или выбери следующий.';
      },
    );
    player.playerStateStream.listen((_) {
      // Playing can change separately from playbackEventStream (audio focus,
      // pause/resume). Keep the Android MediaSession in sync in every case.
      _broadcast();
      _recordListening();
      _maybeAdvance();
    });
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!sleepTimer.active) return;
      if (sleepTimer.expire(DateTime.now())) unawaited(pause());
      revision.value++;
    });
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (player.playing) unawaited(_saveSafely());
    });
  }
  final LibraryStore store;
  final DownloadManager downloads;
  AudioPreferences _audioPreferences = const AudioPreferences();
  AudioPreferences get audioPreferences => _audioPreferences;
  Future<void> _preferenceWrites = Future.value();

  Future<void> setAudioPreferences(AudioPreferences preferences) {
    final account = _account;
    final write = _preferenceWrites.catchError((_) {}).then((_) async {
      if (account == null || account != _account) {
        throw const ZvukException('Аккаунт изменился. Открой настройки снова.');
      }
      await store.put(account, 'audioPreferences', preferences.toJson());
      if (account != _account) return;
      _audioPreferences = preferences;
      downloads.quality = preferences.downloads;
      revision.value++;
    });
    _preferenceWrites = write;
    return write;
  }

  Map<String, Rating> _notificationRatings = {};
  Set<String> _notificationFavorites = {};
  final Set<String> _pendingFavorites = {};

  void setNotificationFavorites(String account, List<Track> favorites) {
    if (_account != account) return;
    _notificationFavorites = favorites.map((t) => t.id).toSet();
    _broadcast();
  }

  void setNotificationRatings(String account, Map<String, Rating> ratings) {
    if (_account != account) return;
    _notificationRatings = Map.of(ratings);
    if (playlist.current != null) {
      mediaItem.add(_item(playlist.current!, playlist.index));
    }
    _broadcast();
  }

  final player = AudioPlayer();
  final playlist = PlaybackQueue();
  final error = ValueNotifier<String?>(null);
  final revision = ValueNotifier<int>(0);
  Future<void> Function(String account, Track track, int delta)?
  onNotificationVote;
  Future<bool> Function(String account, Track track, bool liked)?
  onNotificationFavorite;
  String sourceTitle = 'Очередь';
  bool isShuffled = false, isWave = false;
  AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none;
  final sleepTimer = SleepTimerState();
  bool _startingWave = false;
  final _wave = WaveBuffer();
  WaveSource _waveSource = const WaveSource.personal();
  WaveSource get waveSource => _waveSource;
  WaveOptions _waveOptions = const WaveOptions();
  WaveOptions get waveOptions => _waveOptions;
  int _waveCursor = 0;
  int _waveGeneration = 0;
  Future<void>? _fillingWave;
  bool _waitingNext = false;
  bool get canSkipNext =>
      playlist.hasNext ||
      isWave ||
      (repeatMode == AudioServiceRepeatMode.all && playlist.current != null);
  Track? get nextTrack {
    if (repeatMode == AudioServiceRepeatMode.one) return playlist.current;
    if (playlist.hasNext) return playlist.tracks[playlist.index + 1];
    if (repeatMode == AudioServiceRepeatMode.all &&
        !isWave &&
        playlist.current != null) {
      return playlist.tracks.first;
    }
    return null;
  }

  String get upNextTitle =>
      nextTrack?.title ??
      (isWave ? 'Поток подберёт следующую' : 'Очередь завершится без повтора');

  void _cancelWave() {
    if (_startingWave) {
      _startingWave = false;
      _loading = false;
    }
    _waveGeneration++;
    _wave.cancel();
    _fillingWave = null;
    _waitingNext = false;
    isWave = false;
    _waveSource = const WaveSource.personal();
    _waveCursor = 0;
  }

  Future<List<Track>> _fetchWave(ZvukApi api, int generation) async {
    final page = await api.recommendations(
      _waveSource,
      cursor: _waveCursor,
      options: _waveOptions,
    );
    if (generation == _waveGeneration) _waveCursor = page.cursor;
    return page.tracks;
  }

  Set<String> get _seedExclusion =>
      _waveSource.kind == WaveKind.track ? {_waveSource.id} : {};

  Future<void> cancelWaveStart(WaveSource source) async {
    if (!_startingWave || !identical(_waveSource, source)) return;
    _cancelWave();
    await pause();
  }

  Future<void> startWave({
    WaveSource source = const WaveSource.personal(),
  }) async {
    _cancelWave();
    final waveGeneration = _waveGeneration;
    _waveSource = source;
    _startingWave = true;
    await pause();
    if (waveGeneration != _waveGeneration || !_startingWave) return;
    final generation = _generation;
    final api = _api;
    if (api == null) {
      _startingWave = false;
      error.value = 'Обнови подключение в настройках.';
      return;
    }
    _loading = true;
    _startingWave = true;
    error.value = null;
    _broadcast();
    try {
      final tracks = await _wave.load(
        () => _fetchWave(api, waveGeneration),
        _seedExclusion,
      );
      if (generation != _generation || waveGeneration != _waveGeneration) {
        return;
      }
      if (tracks.isEmpty) {
        throw const ZvukException(
          'Поток пока не подобрал музыку. Попробуй ещё раз.',
        );
      }
      isWave = true;
      repeatMode = AudioServiceRepeatMode.none;
      isShuffled = false;
      sourceTitle = source.queueTitle;
      playlist.replace(tracks, 0);
      _restoredPosition = Duration.zero;
      _publishQueue();
      await _loadAndPlay();
    } catch (e) {
      if (generation == _generation && waveGeneration == _waveGeneration) {
        _startingWave = false;
        _loading = false;
        error.value = e is ZvukException
            ? e.message
            : 'Поток не загрузился. Попробуй снова.';
        _broadcast();
      }
    } finally {
      if (waveGeneration == _waveGeneration) _startingWave = false;
    }
  }

  Future<void> _fillWave() {
    if (!isWave || _api == null) return Future.value();
    if (_fillingWave != null) return _fillingWave!;
    final generation = _waveGeneration, api = _api!;
    final recent = {
      ...playlist.tracks.reversed.take(200).map((t) => t.id),
      ..._seedExclusion,
    };
    late final Future<void> request;
    request =
        (() async {
          final tracks = await _wave.load(
            () => _fetchWave(api, generation),
            recent,
          );
          if (!isWave || generation != _waveGeneration) return;
          for (final track in tracks) {
            playlist.enqueue(track);
          }
          // Keep a useful back history without growing the Android media queue forever.
          if (playlist.index > 200) {
            final remove = playlist.index - 100;
            playlist.replace(
              playlist.tracks.sublist(remove),
              playlist.index - remove,
            );
          }
          _publishQueue();
          await _saveSafely();
        })().whenComplete(() {
          if (identical(_fillingWave, request)) _fillingWave = null;
        });
    _fillingWave = request;
    return request;
  }

  void _prefetchWave() {
    if (isWave && playlist.tracks.length - playlist.index <= 4) {
      unawaited(
        _fillWave().catchError((_) {
          /* Next retries without interrupting audio. */
        }),
      );
    }
  }

  late final Timer _timer, _sleepTicker;
  ZvukApi? _api;
  String? _account;
  bool _loaded = false, _loading = false, _advancing = false;
  bool _historyRecorded = false;
  Future<void> _historyWrite = Future.value();

  void _recordListening() {
    final account = _account, track = playlist.current;
    if (_historyRecorded ||
        !_loaded ||
        _loading ||
        !player.playing ||
        player.processingState != ProcessingState.ready ||
        account == null ||
        track == null) {
      return;
    }
    _historyRecorded = true;
    final at = DateTime.now();
    _historyWrite = _historyWrite
        .then((_) => HistoryStore(store).record(account, track, at))
        .catchError((_) {
          // A history write must never interrupt playback.
        });
  }

  int _generation = 0;
  Duration _restoredPosition = Duration.zero;
  Future<void> _pending = Future.value();

  Duration get position => _loaded ? player.position : _restoredPosition;
  Duration get duration => _loaded
      ? (player.duration ?? Duration(seconds: playlist.current?.duration ?? 0))
      : Duration(seconds: playlist.current?.duration ?? 0);
  bool get loading => _loading;

  void _maybeAdvance() {
    if (_loaded &&
        !_loading &&
        !_advancing &&
        player.playing &&
        player.processingState == ProcessingState.completed) {
      unawaited(_complete());
    }
  }

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // just_audio handles audio focus interruptions and unplugged headphones.
  }

  Future<void> configure(String account, ZvukApi? api) async {
    if (_account != account) {
      _audioPreferences = AudioPreferences.fromJson(
        await store.get(account, 'audioPreferences'),
      );
      downloads.quality = _audioPreferences.downloads;
    }
    await downloads.configure(account, api);
    if (_account == account) {
      _api = api;
      return;
    }
    ++_generation;
    sleepTimer.cancel();
    await pause();
    _cancelWave();
    await player.stop();
    _api = api;
    _account = account;
    _notificationRatings = await store.ratings(account);
    _notificationFavorites = (await store.loadTracks(
      account,
      'favorites',
    )).map((t) => t.id).toSet();
    _loaded = false;
    _historyRecorded = false;
    playlist.replace([], 0);
    sourceTitle = 'Очередь';
    isShuffled = false;
    repeatMode = AudioServiceRepeatMode.none;
    _restoredPosition = Duration.zero;
    _waveOptions = WaveOptions.fromJson(
      await store.get(account, 'waveOptions'),
    );
    final saved = await store.get(account, 'queue');
    if (saved is Map<String, dynamic>) {
      try {
        playlist.restore(saved);
        sourceTitle = saved['title'] as String? ?? 'Очередь';
        isShuffled = saved['shuffled'] == true;
        isWave = saved['wave'] == true;
        if (isWave && saved['waveSource'] != null) {
          try {
            _waveSource = WaveSource.fromJson(
              saved['waveSource'] as Map<String, dynamic>,
            );
            final cursor = saved['waveCursor'];
            _waveCursor = cursor is int && cursor >= 0 ? cursor : 0;
          } catch (_) {
            // Preserve cached queue even if optional flow metadata is damaged.
            isWave = false;
            _waveSource = const WaveSource.personal();
            _waveCursor = 0;
          }
        }
        repeatMode = switch (saved['repeat']) {
          'one' => AudioServiceRepeatMode.one,
          'all' when !isWave => AudioServiceRepeatMode.all,
          _ => AudioServiceRepeatMode.none,
        };
        _restoredPosition = Duration(
          milliseconds: saved['position'] as int? ?? 0,
        );
      } catch (_) {
        playlist.replace([], 0);
      }
    }
    _publishQueue();
    _broadcast();
  }

  MediaItem _item(Track t, int index) => MediaItem(
    id: '${t.id}:$index',
    title: t.title,
    artist:
        '${t.artists.isEmpty ? '' : '${t.artists} · '}Баллы: ${trackScore(t.id, _notificationRatings)}',
    displayTitle: t.title,
    displaySubtitle:
        '${t.artists.isEmpty ? '' : '${t.artists} · '}Баллы: ${trackScore(t.id, _notificationRatings)}',
    duration: Duration(seconds: t.duration),
    artUri: t.imageUrl == null ? null : Uri.tryParse(t.imageUrl!),
    extras: {'trackId': t.id},
  );
  void _publishQueue({bool updateQueue = true}) {
    if (updateQueue) {
      queue.add(
        playlist.tracks
            .asMap()
            .entries
            .map((e) => _item(e.value, e.key))
            .toList(),
      );
    }
    mediaItem.add(
      playlist.current == null
          ? null
          : _item(playlist.current!, playlist.index),
    );
    revision.value++;
  }

  void _broadcast() {
    final wantsPlayback = player.playing || _loading;
    playbackState.add(
      PlaybackState(
        controls: _notificationControls(wantsPlayback),
        systemActions: const {MediaAction.seek, MediaAction.setRepeatMode},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _loading
            ? AudioProcessingState.loading
            : switch (player.processingState) {
                ProcessingState.idle => AudioProcessingState.idle,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: wantsPlayback,
        updatePosition: _loaded ? player.position : _restoredPosition,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        repeatMode: repeatMode,
        queueIndex: playlist.current == null ? null : playlist.index,
      ),
    );
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) =>
      name.startsWith('zvuk.favorite.')
      ? _favoriteFromNotification(name)
      : _rateFromNotification(name);

  Future<void> _save() async {
    final account = _account;
    if (account != null) {
      await store.put(account, 'queue', {
        ...playlist.toJson(),
        'title': sourceTitle,
        'shuffled': isShuffled,
        'wave': isWave,
        if (isWave) 'waveSource': _waveSource.toJson(),
        if (isWave) 'waveCursor': _waveCursor,
        'repeat': repeatMode.name,
        'position':
            (_loaded ? player.position : _restoredPosition).inMilliseconds,
      });
    }
  }

  Future<void> savePosition() => _saveSafely();

  Future<void> _saveSafely() async {
    try {
      await _save();
    } catch (_) {
      error.value = 'Не удалось сохранить позицию в очереди.';
    }
  }

  Future<void> playList(
    List<Track> tracks,
    int index, {
    String title = 'Очередь',
    bool shuffled = false,
  }) async {
    _cancelWave();
    playlist.replace(tracks, index);
    sourceTitle = title;
    isShuffled = shuffled;
    _restoredPosition = Duration.zero;
    _publishQueue();
    await _loadAndPlay();
  }

  Future<void> enqueueTrack(Track track, {bool next = false}) async {
    playlist.enqueue(track, next: next);
    _publishQueue();
    await _saveSafely();
  }

  Future<void> _loadAndPlay({bool autoplay = true}) {
    final generation = ++_generation;
    final track = playlist.current;
    final api = _api, account = _account;
    _loaded = false;
    _historyRecorded = false;
    _loading = track != null && autoplay;
    error.value = null;
    // Stop promptly, then serialize source loading so an older HTTP request
    // can never replace the newest selected song.
    unawaited(player.pause());
    unawaited(_saveSafely());
    _broadcast();
    final position = _restoredPosition;
    _pending = _pending.catchError((_) {}).then((_) async {
      if (generation != _generation) return;
      if (track == null || !autoplay) {
        await player.stop();
        if (generation == _generation) {
          _broadcast();
          await _saveSafely();
        }
        return;
      }
      try {
        final local = account == null
            ? null
            : await downloads.localPath(account, track.id);
        if (generation != _generation) return;
        if (local != null) {
          await player.setFilePath(local, initialPosition: position);
        } else {
          if (api == null) {
            throw const ZvukException(
              'Эта песня не скачана. Подключи Звук и сохрани её для прослушивания без интернета.',
            );
          }
          final url = await api.streamUrl(
            track.id,
            quality: _audioPreferences.streaming,
          );
          if (generation != _generation) return;
          await player.setUrl(url, initialPosition: position);
        }
        if (generation != _generation) return;
        _loaded = true;
        _loading = false;
        _restoredPosition = Duration.zero;
        _broadcast();
        await _saveSafely();
        if (generation != _generation) return;
        unawaited(
          player.play().catchError((_) {
            if (generation == _generation) {
              error.value = 'Поток прервался. Нажми воспроизведение ещё раз.';
            }
          }),
        );
      } catch (e) {
        if (generation == _generation) {
          _loading = false;
          _loaded = false;
          error.value = e is ZvukException ? e.message : 'Трек не загрузился. Проверь сеть и повтори или выбери следующий.';
          await player.stop();
          _broadcast();
        }
      }
    });
    _prefetchWave();
    return _pending;
  }

  @override
  Future<void> play() async {
    if (playlist.current == null) return;
    if (!_loaded) {
      await _loadAndPlay();
      return;
    }
    if (player.processingState == ProcessingState.completed) {
      final generation = _generation;
      _historyRecorded = false;
      await player.seek(Duration.zero);
      if (generation != _generation) return;
    }
    error.value = null;
    unawaited(
      player.play().catchError((_) {
        error.value = 'Поток прервался. Выбери трек ещё раз.';
        _loaded = false;
      }),
    );
  }

  @override
  Future<void> pause() async {
    // Cancel an imminent play even after source loading has finished, while
    // the queue position is still being saved.
    ++_generation;
    _loading = false;
    await player.pause();
    await _saveSafely();
    _broadcast();
  }

  @override
  Future<void> stop() async {
    sleepTimer.cancel();
    revision.value++;
    ++_generation;
    final resumePosition = position;
    await pause();
    _restoredPosition = resumePosition;
    await player.stop();
    _loaded = false;
    _broadcast();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_loaded) {
      await player.seek(position);
    } else {
      _restoredPosition = position;
    }
    await _saveSafely();
    _broadcast();
  }

  @override
  Future<void> skipToNext() async {
    if (_waitingNext) return;
    if (!playlist.hasNext && isWave) {
      _waitingNext = true;
      final generation = _generation;
      _loading = true;
      _broadcast();
      try {
        while (isWave && !playlist.hasNext) {
          final waveGeneration = _waveGeneration;
          try {
            await _fillWave();
          } catch (_) {
            if (waveGeneration != _waveGeneration) continue;
            rethrow;
          }
          if (generation != _generation) return;
          if (waveGeneration == _waveGeneration) break;
        }
        if (generation != _generation || !isWave) return;
        if (!playlist.hasNext) {
          throw const ZvukException(
            'Поток пока не подобрал новые песни. Нажми «Следующая» ещё раз.',
          );
        }
      } catch (e) {
        if (generation == _generation) {
          await pause();
          error.value = e is ZvukException ? e.message : 'Не удалось продолжить поток. Проверь интернет и нажми «Следующая».';
        }
        return;
      } finally {
        if (generation == _generation) {
          _waitingNext = false;
          _loading = false;
          _broadcast();
        }
      }
    }
    if (!playlist.advance()) {
      if (repeatMode == AudioServiceRepeatMode.all &&
          !isWave &&
          playlist.current != null) {
        playlist.jump(0);
      } else {
        await pause();
        return;
      }
    }
    _restoredPosition = Duration.zero;
    _publishQueue(updateQueue: false);
    await _loadAndPlay();
  }

  @override
  Future<void> skipToPrevious() async {
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final moved = playlist.previous();
    final wrap =
        !moved &&
        repeatMode == AudioServiceRepeatMode.all &&
        !isWave &&
        playlist.current != null;
    if (wrap) playlist.jump(playlist.length - 1);
    if (moved || wrap) {
      _restoredPosition = Duration.zero;
      _publishQueue(updateQueue: false);
      await _loadAndPlay();
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= playlist.length) return;
    playlist.jump(index);
    _restoredPosition = Duration.zero;
    _publishQueue(updateQueue: false);
    await _loadAndPlay();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final normalized = repeatMode == AudioServiceRepeatMode.group
        ? AudioServiceRepeatMode.all
        : repeatMode;
    this.repeatMode = isWave && normalized == AudioServiceRepeatMode.all
        ? AudioServiceRepeatMode.none
        : normalized;
    revision.value++;
    _broadcast();
    await _saveSafely();
  }

  Future<void> _complete() async {
    _advancing = true;
    try {
      if (sleepTimer.finishSong() || sleepTimer.expire(DateTime.now())) {
        revision.value++;
        await pause();
      } else if (repeatMode == AudioServiceRepeatMode.one) {
        await play();
      } else if (canSkipNext) {
        await skipToNext();
      } else {
        await pause();
      }
    } finally {
      _advancing = false;
    }
  }

  Future<void> disposeHandler() async {
    _timer.cancel();
    _sleepTicker.cancel();
    await stop();
    _cancelWave();
    await player.dispose();
    await downloads.close();
    await _historyWrite;
    error.dispose();
    revision.dispose();
  }
}
