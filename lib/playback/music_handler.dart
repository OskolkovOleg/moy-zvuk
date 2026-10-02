import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/library_store.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import 'playback_queue.dart';

class MusicHandler extends BaseAudioHandler with SeekHandler {
  MusicHandler(this.store) {
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
      _maybeAdvance();
    });
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (player.playing) unawaited(_saveSafely());
    });
  }
  final LibraryStore store;
  final player = AudioPlayer();
  final playlist = PlaybackQueue();
  final error = ValueNotifier<String?>(null);
  final revision = ValueNotifier<int>(0);
  String sourceTitle = 'Очередь';
  bool isShuffled = false;
  late final Timer _timer;
  ZvukApi? _api;
  String? _account;
  bool _loaded = false, _loading = false, _advancing = false;
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
    if (_account == account) {
      _api = api;
      return;
    }
    ++_generation;
    await pause();
    await player.stop();
    _api = api;
    _account = account;
    _loaded = false;
    playlist.replace([], 0);
    sourceTitle = 'Очередь';
    isShuffled = false;
    _restoredPosition = Duration.zero;
    final saved = await store.get(account, 'queue');
    if (saved is Map<String, dynamic>) {
      try {
        playlist.restore(saved);
        sourceTitle = saved['title'] as String? ?? 'Очередь';
        isShuffled = saved['shuffled'] == true;
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
    artist: t.artists,
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
        controls: [
          MediaControl.skipToPrevious,
          wantsPlayback ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
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
        queueIndex: playlist.current == null ? null : playlist.index,
      ),
    );
  }

  Future<void> _save() async {
    final account = _account;
    if (account != null) {
      await store.put(account, 'queue', {
        ...playlist.toJson(),
        'title': sourceTitle,
        'shuffled': isShuffled,
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

  Future<void> _loadAndPlay() {
    final generation = ++_generation;
    final track = playlist.current;
    final api = _api;
    _loaded = false;
    _loading = track != null;
    error.value = null;
    // Stop promptly, then serialize source loading so an older HTTP request
    // can never replace the newest selected song.
    unawaited(player.pause());
    unawaited(_saveSafely());
    _broadcast();
    final position = _restoredPosition;
    _pending = _pending.catchError((_) {}).then((_) async {
      if (generation != _generation || track == null) return;
      try {
        if (api == null) {
          throw const ZvukException(
            'Обнови подключение в настройках, чтобы слушать музыку.',
          );
        }
        final url = await api.streamUrl(track.id);
        if (generation != _generation) return;
        await player.setUrl(url, initialPosition: position);
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
      await player.seek(Duration.zero);
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
    if (!playlist.advance()) {
      await pause();
      return;
    }
    _restoredPosition = Duration.zero;
    _publishQueue(updateQueue: false);
    await _loadAndPlay();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (playlist.previous()) {
      _restoredPosition = Duration.zero;
      _publishQueue(updateQueue: false);
      await _loadAndPlay();
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    playlist.jump(index);
    _restoredPosition = Duration.zero;
    _publishQueue(updateQueue: false);
    await _loadAndPlay();
  }

  Future<void> _complete() async {
    _advancing = true;
    try {
      if (playlist.hasNext) {
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
    await stop();
    await player.dispose();
    error.dispose();
    revision.dispose();
  }
}
