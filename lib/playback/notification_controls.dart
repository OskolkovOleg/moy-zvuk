part of 'music_handler.dart';

extension _NotificationControls on MusicHandler {
  String _favoriteActionName() =>
      'zvuk.favorite.${_notificationFavorites.contains(playlist.current?.id) ? 'remove' : 'add'}:$_generation:'
      '${Uri.encodeComponent(_account ?? '')}:'
      '${Uri.encodeComponent(playlist.current?.id ?? '')}';

  MediaControl get _favoriteControl {
    final liked = _notificationFavorites.contains(playlist.current?.id);
    return MediaControl.custom(
      androidIcon: liked
          ? 'drawable/ic_favorite'
          : 'drawable/ic_favorite_border',
      label: liked ? 'Убрать из любимого' : 'В любимое',
      name: _favoriteActionName(),
      extras: {'zvukFavorite': liked},
    );
  }

  // The identity travels in the action name too: an old notification must not
  // apply its vote to a new track or a newly connected account.
  String _ratingActionName(int delta) =>
      'zvuk.rate.${delta > 0 ? 'plus' : 'minus'}:$_generation:'
      '${Uri.encodeComponent(_account ?? '')}:'
      '${Uri.encodeComponent(playlist.current?.id ?? '')}';

  bool get _canFavoriteFromNotification =>
      _account != null &&
      playlist.current != null &&
      onNotificationFavorite != null &&
      _api != null;

  List<MediaControl> _notificationControls(bool playing) => [
    if (!_canFavoriteFromNotification) MediaControl.skipToPrevious,
    playing ? MediaControl.pause : MediaControl.play,
    MediaControl.skipToNext,
    // Android media cards have five slots. Keep both rating actions; the
    // previous-track button remains in the full player.
    if (_canFavoriteFromNotification) _favoriteControl,
    if (_account != null &&
        playlist.current != null &&
        onNotificationVote != null) ...[
      MediaControl.custom(
        androidIcon: 'drawable/ic_rating_minus',
        label: 'Минус 1 балл',
        name: _ratingActionName(-1),
        extras: {
          'zvukRatingScore': trackScore(
            playlist.current!.id,
            _notificationRatings,
          ),
        },
      ),
      MediaControl.custom(
        androidIcon: 'drawable/ic_rating_plus',
        label: 'Плюс 1 балл',
        name: _ratingActionName(1),
        extras: {
          'zvukRatingScore': trackScore(
            playlist.current!.id,
            _notificationRatings,
          ),
        },
      ),
    ],
  ];

  Future<bool> _rateFromNotification(String name) async {
    final account = _account, track = playlist.current;
    final vote = onNotificationVote;
    if (account == null || track == null || vote == null) return false;
    final delta = name == _ratingActionName(-1)
        ? -1
        : name == _ratingActionName(1)
        ? 1
        : null;
    if (delta == null) return false;
    try {
      await vote(account, track, delta);
      return true;
    } catch (_) {
      error.value = 'Оценка не сохранилась. Попробуй ещё раз.';
      return false;
    }
  }

  Future<bool> _favoriteFromNotification(String name) async {
    final account = _account, track = playlist.current;
    final favorite = onNotificationFavorite;
    if (account == null ||
        track == null ||
        favorite == null ||
        _api == null ||
        name != _favoriteActionName() ||
        !_pendingFavorites.add('$account:${track.id}')) {
      return false;
    }
    try {
      final saved = await favorite(
        account,
        track,
        !_notificationFavorites.contains(track.id),
      );
      if (saved &&
          _account == account &&
          error.value ==
              'Избранное не изменилось. Проверь подключение и повтори.') {
        error.value = null;
      }
      return saved;
    } catch (_) {
      if (_account == account) {
        error.value = 'Избранное не изменилось. Проверь подключение и повтори.';
      }
      return false;
    } finally {
      _pendingFavorites.remove('$account:${track.id}');
    }
  }
}
